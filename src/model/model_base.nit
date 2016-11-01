# Copyright 2016 Alexandre Terrasa <alexandre@moz-code.org>.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Base model entities and services
module model_base

import config
import sqlite3

# Context for database-related queries
class DBContext
	super FinalizableOnce

	# Connection to the database
	var connection = new Sqlite3DB.open(sqlite_address)

	# Log a database error
	#
	# TODO: Use logger when available
	fun log_sql_error(thrower: Object, query: String) do
		print "Database error: '{connection.error or else "Unknown error"}' in class {thrower.class_name}"
		print "Query was `{query}`"
	end

	# Databse address
	fun sqlite_address: String do return "Missions"

	# What to do when starting a `with` block
	fun start do end
	# What to do when finishing a `with` block
	fun finish do connection.close

	redef fun finalize do connection.close

	# Try selecting data and log errors if there are some
	fun try_select(query: String): nullable Statement do
		var res = connection.select(query)
		if res == null then
			log_sql_error(self, query)
			return null
		end
		return res
	end
end

redef class Statement
	# Use this function with `COUNT` statements for easy retrieval
	fun get_count: Int do
		var cnt = 0
		for i in self do cnt += i[0].to_i
		return cnt
	end
end

# Base model entity
#
# All model entities are serializable to JSON.
abstract class Entity
	super Jsonable
	serialize

	# Context to which the database is linked
	var context: DBContext is noserialize, writable

	redef fun to_json do return serialize_to_json

	# Commit `self` to database
	fun commit: Bool is abstract

	# Insert a new `self` to database
	fun insert: Bool is abstract

	# Basic insertion method for factorization purposes
	protected fun basic_insert(query: String): Bool do
		var db = context.connection
		if not db.execute(query) then
			context.log_sql_error(self, query)
			return false
		end
		return true
	end

	# Update `self` to database
	fun update: Bool is abstract

	# Basic update method for factorization purposes
	protected fun basic_update(query: String): Bool do
		var db = context.connection
		if not db.execute(query) then
			context.log_sql_error(self, query)
			return false
		end
		return true
	end
end

# Any entity which posesses a unique ID
abstract class UniqueEntity
	super Entity
	serialize

	redef fun to_s do return id.to_s
	redef fun ==(o) do return o isa SELF and id == o.id
	redef fun hash do return id

	# `self` unique id.
	var id: Int = -1 is serialize_as "_id", writable

	redef fun commit do
		if id == -1 then return insert
		return update
	end

	redef fun basic_insert(q) do
		var ret = super
		if ret then id = context.connection.last_insert_rowid
		return ret
	end
end

# Entities which are a bridge with status between two entities
#
# These entities do not posess a single ID, but rather several foreign
# keys as primary key.
abstract class BridgeEntity
	super Entity

	# Has `self` been persisted?
	var persisted = false is writable

	redef fun commit do
		if not persisted then return insert
		return update
	end

	redef fun basic_insert(query) do
		var res = super
		if res then persisted = true
		return res
	end
end

# Something that occurs at some point in time
abstract class Event
	super UniqueEntity
	serialize

	# Timestamp when this event occurred.
	var timestamp: Int is lazy, writable do return get_time

	redef fun insert do
		var db = context.connection
		var query = "INSERT INTO events(datetime) VALUES ({timestamp});"
		if not db.execute(query) then
			print "Unable to create new Event"
			return false
		end
		id = db.last_insert_rowid
		return true
	end

	redef fun update do return true
end

# A worker specialized in getting data from Database Statements
abstract class EntityWorker
	# The kind of entity `self` supports
	type ENTITY: Entity

	# Checks the content of a row for compatibility with an object `ENTITY`
	fun check_data(row: StatementRow): Bool do
		var m = row.map
		for i in expected_data do
			if not m.has_key(i) then
				print "Missing data `{i}` in map for `{entity_type}`"
				print "map was {m.join("\n", ": ")}"
				return false
			end
		end
		return true
	end

	# Tries to fetch an entity from a row.
	fun perform(ctx: DBContext, row: StatementRow): nullable ENTITY do
		if not check_data(row) then return null
		return make_entity_from_row(ctx, row)
	end

	# Fetch one `ENTITY` from DB with `query`
	fun fetch_one(ctx: DBContext, query: String): nullable ENTITY do
		var res = ctx.try_select(query)
		if res == null then
			ctx.log_sql_error(self, query)
			return null
		end
		return fetch_one_from_statement(ctx, res)
	end

	# Fetch multiple `ENTITY` from DB with `query`
	fun fetch_multiple(ctx: DBContext, query: String): Array[ENTITY] do
		var res = ctx.try_select(query)
		if res == null then
			ctx.log_sql_error(self, query)
			return new Array[ENTITY]
		end
		return fetch_multiple_from_statement(ctx, res)
	end

	# Fetch multiple `ENTITY` from DB with `rows`
	fun fetch_one_from_statement(ctx: DBContext, row: Statement): nullable ENTITY do
		var ret = fetch_multiple_from_statement(ctx, row)
		if ret.is_empty then return null
		return ret.first
	end

	# Fetch multiple `ENTITY` from DB with `rows`
	fun fetch_multiple_from_statement(ctx: DBContext, rows: Statement): Array[ENTITY] do
		var ret = new Array[ENTITY]
		for i in rows do
			var el = perform(ctx, i)
			if el == null then
				print "Error when deserializing `{entity_type}` from database"
				print "Got `{i.map}`"
				ret.clear
				break
			end
			ret.add el
		end
		return ret
	end

	# Which data is expected in a map?
	fun expected_data: Array[String] is abstract

	# Returns a user-readable version of `ENTITY`
	fun entity_type: String is abstract

	# Buils an entity from a Database Row
	fun make_entity_from_row(ctx: DBContext, row: StatementRow): ENTITY is abstract
end

# Remove inner references from JSON serialization
#
# Override the basic serialization process for the whole app
redef class JsonSerializer

	# Remove caching when saving refs to db
	redef fun serialize_reference(object) do serialize object
end

redef class String
	# Replace sequences of non-alphanumerical characters by underscore.
	# Also trims additional `_` at the beginning and the end of the string.
	# All uppercase alpha characters will be morphed into lowercase.
	#
	# ~~~
	# assert "abcXYZ123_".strip_id == "abcxyz123"
	# assert ", 'A[]\nB#$_".strip_id == "a_b"
	# ~~~
	fun strip_id: String
	do
		var res = new Buffer
		var sp = false
		for c in chars do
			if not c.is_alphanumeric then
				sp = true
				continue
			end
			if sp then
				res.add '_'
				sp = false
			end
			res.add c.to_lower
		end
		var st = 0
		while res[st] == '_' do st += 1
		var ed = res.length - 1
		while res[ed] == '_' do ed -= 1
		return res.to_s.substring(st, ed - st + 1)
	end
end
