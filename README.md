lovelyspriter
=============

Love2d library for [Spriter](http://www.brashmonkey.com/spriter.htm)

Built to support the latest version of Spriter, and replace
[spriter-love2d](http://github.com/capmar/spriter-love2d).


Bugs
====

Still very much in development.

* Doesn't do tweening properly yet.


Usage
=====


```lua
require("lovelyspriter")

function love.load()
  -- SCML file, relative path to load images from
  spriter = LovelySpriter:new("testrun/testrun.scml", "testrun/")

  -- Animation with name
  runAnim = spriter:getAnim("run")
end

function love.update(dt)
  runAnim:update(dt)
end

function love.draw()
  -- Takes the same arguments as regular love.graphics.draw
  runAnim:draw(350, 350)
end
```


Todo
====

* Remove middleclass dependency.
* Write tests.
* Add option to save/read SCML data from a lua cache – to improve load times.

Contact
=======

Send feature request, bugs, feedback to @benhumphreys or via Github
