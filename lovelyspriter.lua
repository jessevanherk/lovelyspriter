-- Read Spriter's SCML format, create something we can render
-- Reads XML so it's a little slow. Also uses lots of middleclass
-- stuff. Will work on speeding things up later.

-- WARNING: SCML indices all start at zero. This converts them to starting
--          from 1 so Lua iterates nicely.
--          If this is causing problems I can change it.

require("middleclass")
require("luaxml")

local lg = love.graphics

local imageData = {}
local function getImage(folderId, imageId)
  return imageData[folderId .. '-' .. imageId]
end

LovelySpriter = class("LovelySpriter")

function LovelySpriter:initialize(xmlFile, customPathPrefix)
  local contents, size = love.filesystem.read(xmlFile)

  local rawData = collect(contents)

  self.animations = {}

  self.imagePathPrefix = customPathPrefix or ''
  
  for i, v in ipairs(rawData[2]) do
    if v.label == "folder" then
      self:parseFolder(v)

    -- Spec says there should only be one entity
    elseif v.label == "entity" then
      local entity = v
      for i, v in ipairs(entity) do
        assert(v.label == "animation", "Unknown child, expecting 'animation', found '" .. v.label .. "'")
        local a = Animation:new(v)
        self.animations[a.name] = a
      end
    else
      error("Unknown child, expecting 'folder' or 'entity', found '" .. v.label .. "'")
    end
  end
end

function LovelySpriter:getAnim(name)
  return self.animations[name]
end

-- Load images
function LovelySpriter:parseFolder(folder)
  local folderId = tonumber(folder.xarg.id) + 1

  for i, file in ipairs(folder) do
    assert(file.label == "file", "Unknown child, expecting 'file', found '" .. file.label .. "'")
    local fileId = tonumber(file.xarg.id) + 1
    local key = folderId .. '-' .. fileId
    imageData[key] = {
      width  = file.xarg.width,
      height = file.xarg.height,
      name   = file.xarg.name,
      image  = lg.newImage(self.imagePathPrefix .. file.xarg.name),
    }
    imageData[key].scaleX = imageData[key].image:getWidth() / imageData[key].width
    imageData[key].scaleY = imageData[key].image:getHeight() / imageData[key].height
  end
end




-------------------------------------------------------------------------------

Animation = class("Animation")

-- Create from raw XML object
function Animation:initialize(anim)
  self.name     = anim.xarg.name   or error("Name required")
  -- Better name
  self.duration = anim.xarg.length or error("Duration required") -- in milliseconds

  self.tween = true -- can turn this off

  self.currentTime     = 0
  self.currentKeyFrame = 0

  self.keyFrames       = {}
  self.objectTimelines = {}

  -- Parse mainline last
  local savedMainline = nil

  for i, v in ipairs(anim) do
    if v.label == "mainline" then
      savedMainline = v
    elseif v.label == "timeline" then
      -- "each <timeline> repesents one persistent object that has scope to the entire animation"
      -- These objects should only be drawn when they are referenced by <object_ref> in a 
      -- <mainline> <key>.
      self:_parseObjectTimeline(v)
    else
      error("Unknown child, expecting 'mainline' or 'timeline', found '" .. v.label .. "'")
    end
  end

  assert(savedMainline, "Must have a mainline")

  self:_parseMainline(savedMainline)

  assert(#self.keyFrames ~= 0, 'should have loaded some keyframes??')
end

function Animation:_parseMainline(mainline)
  for _, v in ipairs(mainline) do
    assert(v.label == "key", "Unknown child, expecting 'key', found '" .. v.label .. "'")
    local keyFrameId = tonumber(v.xarg.id) + 1
    local keyFrame = {
      id   = keyFrameId,
      time = tonumber(v.xarg.time or 0),
      objects = {}
    }

    for _, v2 in ipairs(v) do
      if v2.label == "object" then
        -- Transient object (See manual)
        error("TODO: Transient objects not yet supported")
      elseif v2.label == "object_ref" then
        local objectId   = tonumber(v2.xarg.id) + 1
        local timelineId = tonumber(v2.xarg.id) + 1
        keyFrame.objects[objectId] = self.objectTimelines[objectId][keyFrameId]
          --timelineId = v2.xarg.timeline,
        keyFrame.objects[objectId].zIndex = v2.xarg.z_index
          --zIndex     = v2.xarg.z_index,
        --}
      else
        error("Unknown child, expecting 'object' or 'object_ref', found '" .. v.label .. "'")
      end
    end

    self.keyFrames[keyFrameId] = keyFrame
  end
end

-- The entire timeline for a single object
-- Can tween between these
function Animation:_parseObjectTimeline(timeline)
  local objectId = tonumber(timeline.xarg.id) + 1

  self.objectTimelines[objectId] = {}

  for _, v in ipairs(timeline) do
    assert(v.label == "key", "Unknown child, expecting 'key', found '" .. v.label .. "'")

    local keyFrameId = tonumber(v.xarg.id) + 1

    for _, v2 in ipairs(v) do
      assert(v2.label == "object", "Unknown child, expecting 'object', found '" .. v.label .. "'")
      for key, value in pairs(v2.xarg) do
        print(key, "\t", value)
      end

      local objProps = v2.xarg
      self.objectTimelines[objectId][keyFrameId] = Object:new(
        objProps.x,
        objProps.y,
        tonumber(objProps.folder) + 1,
        tonumber(objProps.file) + 1,
        objProps.pivot_x,
        objProps.pivot_y,
        objProps.angle
      )
    end
  end
end


-- Call every tick please
function Animation:update(dt)
  self.currentTime = self.currentTime + (dt*1000)
  self.currentTime = self.currentTime % self.duration

  -- percent is the % through the current keyframe. Used for tweening

  for i = 1, #self.keyFrames do
    local time = self.keyFrames[i].time
    --print(self.currentTime, " > ", time, " ?")
    if self.currentTime > time then
      self.currentKeyFrame = self.keyFrames[i]

      -- Next keyFrame
      local nI = (i + 1)
      if nI > #self.keyFrames then nI = 1 end
      self.nextKeyFrame    = self.keyFrames[nI]
      assert(self.nextKeyFrame, "Messed up")

      -- If nextKeyFrame is wrapped around then...
      local nextTime = self.nextKeyFrame.time
      if nI < i then
        nextTime = nextTime + self.duration
      end
      self.percent = (self.currentTime - self.currentKeyFrame.time) / (nextTime - self.currentKeyFrame.time)
    end
  end
end

function Animation:draw(...)
  if self.tween then
    Animation._drawTweenedFrames(
      self.currentKeyFrame,
      self.nextKeyFrame,
      self.percent,
      ...
    )
  else
    Animation._drawFrame(self.currentKeyFrame, ...)
  end
end

function Animation._drawTweenedFrames(frame1, frame2, percent, x, y, r, sx, sy, ox, oy)
  assert(frame1, "need frame")
  assert(frame2, "need frame")

	r  = r  or 0
	sx = sx or 1
	sy = sy or sx
	ox = ox or 0
	oy = oy or 0

	lg.push()
    lg.translate(x, y)
    lg.rotate(r)
    lg.scale(sx, sy)
    lg.translate(-ox, -oy)

    -- Sort objects in z-depth order
    local objects1 = frame1.objects
    table.sort(objects1, function(a, b) return a.zIndex > b.zIndex end)  

    local objects2 = frame2.objects
    table.sort(objects2, function(a, b) return a.zIndex > b.zIndex end)  

    assert(#objects1 == #objects2)
    for i = 1, #objects1 do
      tweened = objects1[i]:tween(objects2[i], percent)
      tweened:draw()
    end
	lg.pop()
  
end


function Animation._drawFrame(frame, x, y, r, sx, sy, ox, oy)
  assert(frame, "need frame")
	r  = r  or 0
	sx = sx or 1
	sy = sy or sx
	ox = ox or 0
	oy = oy or 0

	lg.push()
    lg.translate(x, y)
    lg.rotate(r)
    lg.scale(sx, sy)
    lg.translate(-ox, -oy)

    -- Sort objects in z-depth order
    local objects = frame.objects
    table.sort(objects, function(a, b) return a.zIndex > b.zIndex end)  

    for _, object in ipairs(objects) do
      object:draw()
    end
	lg.pop()
end


-------------------------------------------------------------------------------

Object = class("Object")

function Object:initialize(x, y, folderId, imageId, pivotX, pivotY, angle)
  self.x        =  x or error("Need X")
  self.y        = -y or error("Need Y") -- y goes upwards

  self.folderId = folderId or error("Need folder ID")
  self.imageId  = imageId  or error("Need image ID")
  
  -- Pivot is range 0--1, bottom-left is 0,0
  self.pivotX   = pivotX or 0
  self.pivotY   = 1 - (pivotY or 1)

  self.angle    = -1 * math.rad(angle or 0) -- counter-clockwise... ok
end

function Object:draw()
  lg.setPointSize(5)
  -- TODO: Color
  --local r, g, b = parseColor(sprite.color)
  --local a = (self.opacity / 100) * 255
  
  -- Origin



  local img = getImage(self.folderId, self.imageId)
  --if self.imageId ~= 1 then return end

  lg.setColor(0,255,0,128)
  lg.rectangle('line', self.x, self.y, img.width, img.height)

  lg.setColor(0,255,255,255)
  lg.point(0, 0)

  lg.setColor(0,255,0,255)
  lg.point(self.x, self.y)

  lg.push()
    --local pX = self.x + (img.width  * self.pivotX)
    --local pY = self.y + (img.height * self.pivotY)
    local pX = (img.width  * self.pivotX)
    local pY = (img.height * self.pivotY)


    lg.translate(pX, pY)
    lg.rotate(self.angle)
    lg.translate(-pX, -pY)

    lg.setColor(0,255,0,128)
    lg.rectangle('line', self.x, self.y, img.width, img.height)
    --print(pX, pY)
    lg.setColor(255,0,0,255)
    lg.point(pX, pY)

    lg.setColor(255,0,255,255)
    lg.point(self.pivotX, self.pivotY)

    -- TODO: Rotation
    lg.setColor(255,255,255,255)
    lg.draw(img.image, self.x, self.y) --, 0, img.scaleX, img.scaleY) --, self.angle)
    --lg.draw(img.image, self.x, self.y, self.angle, 1, 1, pX, pY) --, 0, img.scaleX, img.scaleY) --, self.angle)
  lg.pop()
end

local function mix(a, b, ratio)
	return a * (1 - ratio) + b * ratio
end

local function shortestAngle(from, to)
  local pi2 = math.pi * 2
  local pi =  math.pi

	from = from % pi2
	to   = to   % pi2

	local angle = to - from
	if pi < angle then
		angle = angle - pi2
	elseif angle < -pi then
		angle= angle + pi2
	end

	return angle
end

function Object:tween(o2, percent, method)
  method = method or "linear"
  assert(method == "linear", "Other tweening methods not yet supported")
  assert(o2.imageId == self.imageId, "Can't tween between different images")

  local short = shortestAngle(self.angle, o2.angle)

  return Object:new(
    mix(self.x, o2.x, percent),
    mix(self.y, o2.y, percent),
    self.folderId,
    self.imageId,
    pivotX, --mix(self.pivotX, o2.pivotX, percent),
    pivotY, --mix(self.pivotY, o2.pivotY, percent),
    mix(self.angle, self.angle+short, percent)
  )
end

