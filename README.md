lovelyspriter
=============

Love2d library for [Spriter](http://www.brashmonkey.com/spriter.htm)

Built to support the latest version of Spriter, and replace
[spriter-love2d](http://github.com/capmar/spriter-love2d).


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


Extras
======

```lua
-- Turn on drawing debugging information
LovelySpriter.DRAW_BOUNDING    = true
LovelySpriter.DRAW_PIVOT_POINT = true
```

```lua
-- Toggle tweening
runAnim = spriter:getAnim("run")
runAnim.tween = false
```

```lua
-- Change animation speed
function love.update(dt)
  local animDt = dt * sprite.runSpeed
  runAnim:update(animDt)
end
```


Todo
====

* Animations with single frames
* Bone support
* Easier interface for changing animation speed
* Completely remove dependency on middleclass
* Write tests
* Add option to save/read SCML data from a lua cache – to improve load times


Contact
=======

Send feature request, bugs, feedback to @benhumphreys or via Github

