local lg = love.graphics

require("lovelyspriter")

function love.load()
  spriter = LovelySpriter:new('testrun/testrun.scml', 'testrun/')
  runAnim = spriter:getAnim("run")

  local w, h, f, v, a = lg.getMode()
  local success = lg.setMode(w, h, f, not v, a)
  if not success then
    print("ERROR: Failed to toggle VSync")
    lg.setMode(w, h, f, v, a)
  end
end

function love.update(dt)
  runAnim:update(dt)
end

function love.draw()
  runAnim:draw(350, 350)

  -- showfps
  lg.setColor(255,0,0,255)
  lg.print(tostring(love.timer.getFPS()), lg.getWidth()-30, lg.getHeight()-20)
end
