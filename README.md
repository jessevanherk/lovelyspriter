lovelyspriter
=============

Love2d library for [Spriter](http://www.brashmonkey.com/spriter.htm)

Built to support the latest version of Spriter, and replace
[spriter-love2d](http://github.com/capmar/spriter-love2d).


Bugs
====

Still very much in development.

Uses middleclass at the moment but I'll update it later to remove that
dependency.


Usage
=====

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
