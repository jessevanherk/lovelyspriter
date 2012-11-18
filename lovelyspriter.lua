-- Read Spriter's SCML format, create something we can render
-- Reads XML so it's a little slow. Also uses lots of middleclass
-- stuff. Will work on speeding things up later.

-- WARNING: SCML indices all start at zero. This converts them to starting
--          from 1 so Lua iterates nicely.
--          If this is causing problems I can change it.

require("middleclass")
local luaxml = require("luaxml")

local lg = love.graphics

local imageData = {}
local function getImage(folderId, imageId)
  return imageData[folderId .. '-' .. imageId]
end


LovelySpriter = class("LovelySpriter")
LovelySpriter.VERSION = 4.1


function LovelySpriter:initialize(xmlFile, customPathPrefix)
  local contents, size = love.filesystem.read(xmlFile)

  local rawData = luaxml.collect(contents) -- Load XML into Lua datastruct

  -- Check the file isn't too old or newer than us
  local version = tonumber(string.sub(rawData[2].xarg.generator_version, 2))
  if version > LovelySpriter.VERSION then
    print("WARNING: File version (" .. version .. ") greater than " ..
          "LovelySpriter (" .. LovelySpriter.VERSION .. "), bugs may ensue.")
  elseif version < LovelySpriter.VERSION - 1 then
    print("WARNING: File version (" .. version .. ") significantly earlier than " ..
          "LovelySpriter (" .. LovelySpriter.VERSION .. "), bugs may ensue.")
  end

  self.animations = {}

  self.imagePathPrefix = customPathPrefix or ''
  
  for i, v in ipairs(rawData[2]) do
    if v.label == "folder" then
      self:loadImages(v)

    -- Spec says there should only be one entity
    elseif v.label == "entity" then
      local entity = v
      for i, v in ipairs(entity) do
        assert(v.label == "animation", "Unknown child, expecting 'animation', found '" .. v.label .. "'")
        local a = Animation:new(v)
        if self.animations[a.name] then
          error("Multiple animations with the same name: " .. a.name)
        end
        self.animations[a.name] = a
      end
    else
      error("Unknown child, expecting 'folder' or 'entity', found '" .. v.label .. "'")
    end
  end
end


function LovelySpriter:getAnim(name)
  assert(self.animations[name], "Unknown animation '" .. name .. "'")
  return self.animations[name]
end


function LovelySpriter:loadImages(folder)
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
        keyFrame.objects[objectId].zIndex = tonumber(v2.xarg.z_index) or error("Z-index undef")
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

    local spin = tonumber(v.xarg.spin or 1) -- -1 for counter-clockwise

    local keyFrameId = tonumber(v.xarg.id) + 1

    for _, v2 in ipairs(v) do
      assert(v2.label == "object", "Unknown child, expecting 'object', found '" .. v.label .. "'")
      for key, value in pairs(v2.xarg) do
        print(key, "\t", value)
      end

      local objProps = v2.xarg

      -- Object is now a table not a Lua 'object'
      -- Because tweening to create new objects was crazyballs
      -- object:new
      self.objectTimelines[objectId][keyFrameId] = {
        x        = tonumber(objProps.x),
        y        = -1 * (tonumber(objProps.y) or 0), -- range is negative
        folderId = tonumber(objProps.folder) + 1, -- conv to base 1
        imageId  = tonumber(objProps.file) + 1,
        pivotX   = tonumber(objProps.pivot_x) or 0,
        pivotY   = 1 - (tonumber(objProps.pivot_y) or 1),
        angle    = -1 * (math.rad(tonumber(objProps.angle) or 0)),
        spinDir  = spin or 0,
      }
    end
  end
end


-- Call every tick please
-- To update faster or slower, pass in modified dt
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
    table.sort(objects, function(a, b) return a.zIndex < b.zIndex end)  

    for _, object in ipairs(objects) do
      Animation.drawObject(object)
    end
	lg.pop()
end


function Animation._drawTweenedFrames(frame1, frame2, percent, x, y, r, sx, sy, ox, oy)
  assert(frame1, "need frame")
  assert(frame2, "need frame")

	r  =  r or 0
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
    table.sort(objects1, function(a, b) return a.zIndex < b.zIndex end)  

    local objects2 = frame2.objects
    table.sort(objects2, function(a, b) return a.zIndex < b.zIndex end)  

    assert(#objects1 == #objects2)

    for i = 1, #objects1 do
      tweened = Animation.tweenObject(objects1[i], objects2[i], percent)
      --print(objects1[i])
      --print(objects2[i])
      --print(percent)
      --print(tweened)
      --print("------------")
      Animation.drawObject(tweened)
    end
	lg.pop()
  
end



--function Object:initialize(x, y, folderId, imageId, pivotX, pivotY, angle, spin)
  --self.x = x or 0
  --self.y = y or 0 -- example files have no y coord
  --self.y = -self.y -- Spriter y-axis is backwards

  --if not y then
    --print("WARNING: no Y component")
  --end

  --self.folderId = folderId or error("Need folder ID")
  --self.imageId  = imageId  or error("Need image ID")
  
  ---- SCML pivot is range 0--1, bottom-left is 0,0
  --self.pivotX   = pivotX or 0
  --self.pivotY   = 1 - (pivotY or 1)

  --self.angle    = -1 * math.rad(angle or 0) -- counter-clockwise... ok

  --self.spin = spin or 1
--end



-------------------------------------------------------------------------------

Object = class("Object")


function Animation.drawObject(object)
  lg.setPointSize(5)

  local img = getImage(object.folderId, object.imageId)
  --if object.imageId ~= 1 then return end

  lg.setColor(0,255,0,128)
  lg.rectangle('line', object.x, object.y, img.width, img.height)

  lg.setColor(0,255,255,255)
  lg.point(0, 0)

  lg.setColor(0,255,0,255)
  lg.point(object.x, object.y)

  lg.push()
    --local pX = object.x + (img.width  * object.pivotX)
    --local pY = object.y + (img.height * object.pivotY)
    local pX = (img.width  * object.pivotX)
    local pY = (img.height * object.pivotY)

    local r = object.angle
    if object.spin == -1 then
      r = r - (math.pi*2)
    end

    --lg.translate(pX, pY)
    --lg.rotate(object.angle)
    --lg.translate(-pX, -pY)

    lg.setColor(0,255,0,128)
    lg.rectangle('line', object.x, object.y, img.width, img.height)
    --print(pX, pY)
    lg.setColor(255,0,0,255)
    lg.point(pX, pY)

    lg.setColor(255,0,255,255)
    lg.point(object.pivotX, object.pivotY)

    -- TODO: Rotation
    lg.setColor(255,255,255,255)
    --lg.draw(img.image, self.x, self.y) --, 0, img.scaleX, img.scaleY) --, self.angle)
    lg.draw(img.image, object.x, object.y, r, 1, 1, pX, pY) --, 0, img.scaleX, img.scaleY) --, self.angle)
  lg.pop()
end


local function mix(a, b, ratio)
	return a * (1 - ratio) + b * ratio
end


local function shortestAngle(from, to)
  local pi2 = math.pi * 2
  local pi  = math.pi

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


local function rotation(from, to, direction)
  local pi2 = math.pi * 2
  local pi  = math.pi

  local diff = to - from
  if direction == 1 then -- clockwise
    if diff > 0 then
      to = to - pi2
    end
  else -- counterclockwise
    if diff < 0 then
      to = to + pi2
    end
  end

	return to
end


function Animation.tweenObject(o1, o2, percent, method)
  method = method or "linear"
  assert(method == "linear", "Other tweening methods not yet supported")
  --assert(o2.imageId == self.imageId, "Can't tween between different images: " .. self.imageId .. ' and ' .. o2.imageId)

  assert(o1.pivotX == o2.pivotX, "Make sure the pivot points are the same")
  assert(o1.pivotY == o2.pivotY, "Make sure the pivot points are the same")

  -- object:new
  return {
    x        = mix(o1.x, o2.x, percent),
    y        = mix(o1.y, o2.y, percent),
    folderId = o2.folderId,
    imageId  = o2.imageId,
    pivotX   = o1.pivotX, --mix(o1.pivotX, o2.pivotX, percent),
    pivotY   = o1.pivotY, --mix(o1.pivotY, o2.pivotY, percent),
    angle    = mix(o1.angle, rotation(o1.angle, o2.angle, o1.spinDir), percent),
    spinDir  = o1.spinDir
  }
end

function Animation.objectToString(object)
  return object.x or 'nil' .. "\t" .. object.y or 'nil'  .. "\t" .. object.imageId or 'nil' .. "\t" .. object.folderId or 'nil' .. "\t" .. object.pivotX or 'nil' .. "\t" .. object.pivotY or 'nil' .. "\t" .. object.angle or 'nil' .. "\t" .. object.spinDir or 'nil'
end
