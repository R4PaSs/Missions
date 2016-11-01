DROP TABLE IF EXISTS players;
DROP TABLE IF EXISTS friends;
DROP TABLE IF EXISTS category;
DROP TABLE IF EXISTS tracks;
DROP TABLE IF EXISTS missions;
DROP TABLE IF EXISTS mission_dependencies;
DROP TABLE IF EXISTS testcases;
DROP TABLE IF EXISTS stars;
DROP TABLE IF EXISTS track_status;
DROP TABLE IF EXISTS mission_status;
DROP TABLE IF EXISTS star_status;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS submissions;
DROP TABLE IF EXISTS friend_events;
DROP TABLE IF EXISTS achievements;
DROP TABLE IF EXISTS notifications;
DROP TABLE IF EXISTS achievement_unlocks;
DROP TABLE IF EXISTS languages;
DROP TABLE IF EXISTS track_languages;
DROP TABLE IF EXISTS mission_languages;
DROP TABLE IF EXISTS track_statuses;
DROP TABLE IF EXISTS star_results;


CREATE TABLE players(
	id 		INTEGER PRIMARY KEY 	AUTOINCREMENT,
	slug		TEXT			UNIQUE NOT NULL,
	name 		TEXT			DEFAULT "",
	email		TEXT			DEFAULT "",
	avatar_url	TEXT			DEFAULT "",
	date_joined 	INTEGER 		NOT NULL
);

CREATE TABLE friends(
	player_id1 	INTEGER,
	player_id2 	INTEGER,

	PRIMARY KEY(player_id1, player_id2),
	FOREIGN KEY(player_id1) REFERENCES players(id),
	FOREIGN KEY(player_id2) REFERENCES players(id)
);

CREATE TABLE languages(
	id		INTEGER PRIMARY KEY	AUTOINCREMENT,
	name		TEXT
);

CREATE TABLE tracks(
	id 		INTEGER PRIMARY KEY 	AUTOINCREMENT,
	slug		TEXT			UNIQUE NOT NULL,
	title 		TEXT 			NOT NULL,
	description	TEXT			DEFAULT "",
	path		TEXT
);

CREATE TABLE track_languages(
	track_id	INTEGER,
	language_id	INTEGER,

	PRIMARY KEY(track_id, language_id),
	FOREIGN KEY(track_id) REFERENCES tracks(id),
	FOREIGN KEY(language_id) REFERENCES languages(id)
);

CREATE TABLE track_statuses(
	track_id	INTEGER,
	player_id	INTEGER,
	status		INTEGER,

	PRIMARY KEY(track_id, player_id),
	FOREIGN KEY(track_id) REFERENCES tracks(id),
	FOREIGN KEY(player_id) REFERENCES players(id)
);

CREATE TABLE missions(
	id 		INTEGER PRIMARY KEY 	AUTOINCREMENT,
	slug		TEXT			UNIQUE NOT NULL,
	title 		TEXT 			NOT NULL,
	track_id 	INTEGER 		NOT NULL,
	description	TEXT			NOT NULL,
	reward 		INTEGER 		DEFAULT 0,
	path		TEXT,

	FOREIGN KEY(track_id) REFERENCES tracks(id)
);

CREATE TABLE mission_languages(
	mission_id	INTEGER,
	language_id	INTEGER,

	PRIMARY KEY(mission_id, language_id),
	FOREIGN KEY (mission_id) REFERENCES missions(id),
	FOREIGN KEY (language_id) REFERENCES languages(id)
);

CREATE TABLE mission_dependencies(
	mission_id 	INTEGER 		NOT NULL,
	parent_id 	INTEGER 		NOT NULL,
	PRIMARY KEY (mission_id, parent_id),

	FOREIGN KEY(mission_id) REFERENCES missions(id),
	FOREIGN KEY(parent_id) REFERENCES missions(id)
);

CREATE TABLE testcases(
	id 		INTEGER PRIMARY KEY 	AUTOINCREMENT,
	mission_id 	INTEGER 		NOT NULL,
	root_uri	TEXT			NOT NULL,

	FOREIGN KEY(mission_id) REFERENCES missions(id)
);

CREATE TABLE stars(
	id 		INTEGER PRIMARY KEY 	AUTOINCREMENT,
	title		TEXT			NOT NULL,
	mission_id 	INTEGER 		NOT NULL,
	score 		INTEGER 		DEFAULT 0,
	reward		INTEGER			DEFAULT 0,
	type_id		INTEGER 		NOT NULL,

	FOREIGN KEY(mission_id) REFERENCES missions(id)
);

CREATE TABLE mission_status(
	mission_id	INTEGER,
	player_id	INTEGER,
	status 		INTEGER			NOT NULL,
	PRIMARY KEY(mission_id, player_id),

	FOREIGN KEY(mission_id) REFERENCES missions(id),
	FOREIGN KEY(player_id) REFERENCES players(id)
);

CREATE TABLE star_status(
	star_id		INTEGER,
	player_id	INTEGER,
	status 		BOOLEAN			DEFAULT FALSE,
	PRIMARY KEY(star_id, player_id),

	FOREIGN KEY(star_id) REFERENCES stars(id),
	FOREIGN KEY(player_id) REFERENCES players(id)
);

CREATE TABLE events(
	id 		INTEGER PRIMARY KEY 	AUTOINCREMENT,
	datetime 	INTEGER 		NOT NULL
);

CREATE TABLE submissions(
	event_id 	INTEGER PRIMARY KEY,
	player_id 	INTEGER 		NOT NULL,
	mission_id	TEXT 			NOT NULL,
	workspace_path	TEXT,
	status 		INTEGER 		DEFAULT 1,

	FOREIGN KEY(event_id) REFERENCES events(id),
	FOREIGN KEY(player_id) REFERENCES players(id),
	FOREIGN KEY(mission_id) REFERENCES missions(id)
);

CREATE TABLE friend_events(
	event_id 	INTEGER PRIMARY KEY,
	player_id1 	INTEGER 		NOT NULL,
	player_id2 	INTEGER 		NOT NULL,
	status 		INTEGER			DEFAULT 0,

	FOREIGN KEY(event_id) REFERENCES events(id),
	FOREIGN KEY(player_id1) REFERENCES players(id),
	FOREIGN KEY(player_id2) REFERENCES players(id)
);

CREATE TABLE achievements(
	id		INTEGER	PRIMARY KEY 	AUTOINCREMENT,
	slug		TEXT			UNIQUE NOT NULL,
	title		TEXT			NOT NULL,
	description	TEXT,
	reward		INTEGER			DEFAULT 0
);

CREATE TABLE achievement_unlocks(
	event_id 	INTEGER PRIMARY KEY,
	achievement_id	INTEGER,
	player_id 	INTEGER,

	FOREIGN KEY(event_id) REFERENCES events(id),
	FOREIGN KEY(player_id) REFERENCES players(id),
	FOREIGN KEY(achievement_id) REFERENCES achievements(id)
);

CREATE TABLE notifications(
	id		INTEGER PRIMARY KEY	AUTOINCREMENT,
	event_id 	INTEGER 		NOT NULL,
	player_id 	INTEGER 		NOT NULL,
	object		TEXT			NOT NULL,
	body 		TEXT			DEFAULT "",
	read		BOOLEAN			DEFAULT FALSE,
	timestamp	INTEGER			NOT NULL,

	FOREIGN KEY(event_id) REFERENCES events(id),
	FOREIGN KEY(player_id) REFERENCES players(id)
);

CREATE TABLE star_results(
	id		INTEGER PRIMARY KEY	AUTOINCREMENT,
	submission_id	INTEGER			NOT NULL,
	star_id		INTEGER			NOT NULL,
	score		INTEGER			NOT NULL,

	FOREIGN KEY(submission_id) REFERENCES submissions(event_id),
	FOREIGN KEY(star_id) REFERENCES stars(id)
);
