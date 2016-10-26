# Visit of the Fangorn Forest

The main use of `nitcc` is the generation of the classes, AST and visit methods.
Take a look around the generated files for more insight on how it works.

Let's focus on the Logolas format.

There is an abstract cursor (atùin in Elvish) that starts at (0,0) and is oriented to the right (because elves like to be right).
The x axis is oriented left and the y axis is oriented towards the bottom.

There are 3 basic command types:

* forward (`⭡`) is used to advance in the current direction, the distance is given by the following number (from 1 to 12).
  Because elves like purity, the final position must be rounded to the nearest integer for x and y. It means that between commands, the atùin is always at an integer position.
* turn left (`⮢`) and right (`⮣`) change the current direction.
  The angle is given from 1 to 12, much like a clock (3 means a 90° angle).
* sequences enclosed between `𝄆` and `𝄇` are repeated a given number of times indicated after the closing `𝄇`.
  Note that `Ⅴ` repetitions means that the sequence must be executed 6 times.

## Mission

* Difficulty: advanced

Using the classes generated by nitcc, implement a program that computes the final position of the atùin. The logolas file is given as the first argument of the program.

To help you, three logolas files are proposed:

* an elegant and abstract L letter [maenas](maenas.logolas).
* a glowing and inspiring star [elen](elen.logolas).
* a peaceful and warm house [bar](bar.logolas).

### Template to Use

<!--
~~~nit
module logolas

import logolas_parser
import logolas_lexer

# CODE HERE
~~~-->

<pre class="hl"><span class="hl kwa">module</span> logolas

<span class="hl kwa">import</span> logolas_parser
<span class="hl kwa">import</span> logolas_lexer

<span class="hl slc"># CODE HERE</span>
</pre>

### Expected Result

* for maenas: (1,3)
* for elen: (10,-3)
* for bar: (4,0)