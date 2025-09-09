-- mostly adapted from normal.lua so this is kind of a freaking mess, not gonna lie

local file = ...
local randomindex = math.random(1, 12)

local anim_data = {
	color_add = {-0.75,0,0,-0.75,-0.75,-0.75,0,-0.75,0,-0.75},
	diffusealpha = {0.05,0.2,0.1,0.1,0.1,0.1,0.1,0.05,0.1,0.1},
	xy = {0,40,80,120,200,280,360,400,480,560},
	texcoordvelocity = {{0.03,0.01},{0.03,0.02},{0.03,0.01},{0.02,0.02},{0.03,0.03},{0.02,0.02},{0.03,0.01},{-0.03,0.01},{0.05,0.03},{0.03,0.04}}
}

local t = Def.ActorFrame {
	InitCommand=function(self)
		local style = ThemePrefs.Get("VisualStyle")
		self:visible(style == "Technique")
	end,
	OnCommand=function(self) self:fov(90):accelerate(0.8):diffusealpha(1) end,
	HideCommand=function(self) self:visible(false) end,

	VisualStyleSelectedMessageCommand=function(self)
		local style = ThemePrefs.Get("VisualStyle")
		if style == "Technique" then
			self:visible(true):linear(0.6):diffusealpha(1)
		else
			self:linear(0.6):diffusealpha(0):queuecommand("Hide")
		end
	end,

    LoopCommand=function(self)
		index = index + 1
		self:queuecommand("NewColor"):sleep(delay):queuecommand("Loop")
	end,
}

-- fricks sake this function is giving me so much damn mileage lol
local function randomXD(t)
	if t == 0 then return 0.5 else
	return (math.sin(t * 3229.3) * 43758.5453) % 1 end
end

-- background
t[#t+1] = Def.Quad {
	InitCommand=function(self)
		self:diffuse(20/255, 20/255, 20/255, 1):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
        if ThemePrefs.Get("RainbowMode") then
			self:diffusealpha(0)
		end
	end
}

-- grid i think
t[#t+1] = Def.Sprite {
	Texture = "./square.png",
	OnCommand=function(self)
		self:zoom(20):xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
		:customtexturerect(0,0,60,60):texcoordvelocity(0.05, 0.07)
		:diffusealpha(0.1)
        if ThemePrefs.Get("RainbowMode") then
			self:diffusealpha(0.15)
		end
	end
}
t[#t+1] = Def.Sprite {
	Texture = "./square.png",
	OnCommand=function(self)
		self:zoom(20):xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
		:customtexturerect(0,0,60,60):texcoordvelocity(0.04, 0.02)
		:diffusealpha(0.05)
        if ThemePrefs.Get("RainbowMode") then
			self:diffusealpha(0.2)
		end
	end
}
t[#t+1] = Def.Sprite {
	Texture = "./square.png",
	OnCommand=function(self)
		self:zoom(20):xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
		:customtexturerect(0,0,60,60):texcoordvelocity(0.02, 0.015)
		:diffusealpha(0.025)
        if ThemePrefs.Get("RainbowMode") then
			self:diffusealpha(0.25)
		end
	end
}

-- main stuff (rings, arrow)
for i=1,10 do
	t[#t+1] = Def.Model {
        Meshes="circlefrag_model.txt",
        Materials="circlefrag_model.txt",
        Bones="circlefrag_model.txt",
            InitCommand=function(self)
                self:diffuse(GetHexColor(SL.Global.ActiveColorIndex+anim_data.color_add[i], true)):baserotationz(randomXD(i) * 400):baserotationx(-60):baserotationy(20)
                :SetTextureFiltering(true)
                :diffusealpha(randomXD(i))

            if ThemePrefs.Get("RainbowMode") then
				self:diffuse(GetHexColor(randomindex+anim_data.color_add[i], true))
				self:diffusealpha(self:GetDiffuseAlpha() / 2)
			end
		end,
		OnCommand=function(self)
			self:zoom((randomXD(i*1.6) + 0.35)):xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):z((randomXD(i * 13) - 0.6) * (1 / self:GetZoom()) * 850)
			self:spin():effectmagnitude(0, 0, randomXD(i*3.4) * 14):effectoffset(randomXD(i*1.2) * 400)
		end,
        ColorSelectedMessageCommand=function(self)
            self:diffuse(GetHexColor(SL.Global.ActiveColorIndex+anim_data.color_add[i], true)):diffusealpha(randomXD(i))
        end
	}
end

t[#t+1] = Def.Model {
	Meshes="ring_model.txt",
	Materials="ring_model.txt",
	Bones="ring_model.txt",
	InitCommand=function(self)
		self:diffuse(1, 1, 1, 0.8):baserotationz(50):baserotationx(-60):baserotationy(20)
		:SetTextureFiltering(true)
	end,
	OnCommand=function(self)
		self:zoom(1.75):xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):z(0)
		self:spin():effectmagnitude(0, 0, 10):effectoffset(20)
	end
}

t[#t+1] = Def.Model {
	Meshes="ring_model.txt",
	Materials="ring_model.txt",
	Bones="ring_model.txt",
	InitCommand=function(self)
		self:diffuse(1, 1, 1, 0.8):baserotationz(50):baserotationx(-60):baserotationy(20)
		:SetTextureFiltering(true)
	end,
	OnCommand=function(self)
		self:zoom(0.75):xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):z(0)
		self:spin():effectmagnitude(0, 0, 4):effectoffset(20)
	end
}

t[#t+1] = Def.Model {
	Meshes="arrow_model.txt",
	Materials="arrow_model.txt",
	Bones="arrow_model.txt",
	InitCommand=function(self)
		self
		:diffuse(GetHexColor(SL.Global.ActiveColorIndex, true))
		:baserotationz(20)
		:SetTextureFiltering(true)
		:diffusealpha(0.7)

        if ThemePrefs.Get("RainbowMode") then
			self:diffuse(GetHexColor(randomindex, true))
			self:diffusealpha(0.4)
		end
	end,
	OnCommand=function(self)
		self:zoom(1.2):xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
		self:spin():effectmagnitude(0, 10, 0)
	end,
    ColorSelectedMessageCommand=function(self)
        self:diffuse(GetHexColor(SL.Global.ActiveColorIndex, true)):diffusealpha(0.7)
    end
}

for i=11,18 do
    t[#t+1] = Def.Model {
        Meshes="circlefrag_model.txt",
        Materials="circlefrag_model.txt",
        Bones="circlefrag_model.txt",
        InitCommand=function(self)
            self:diffuse(1, 1, 1, randomXD(i / 1.6)):baserotationz(randomXD(i) * 2000):baserotationx(-60):baserotationy(20)
            :SetTextureFiltering(true)
        end,
        OnCommand=function(self)
            self:zoom((randomXD(i*2.8) + 0.35)):xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):z((randomXD(i * 13) - 0.6) * (2 / self:GetZoom()) * 850)
            self:spin():effectmagnitude(0, 0, randomXD(i*3.6) * 14):effectoffset(i * 2000)
        end
    }
end

--[=====[
Summary: the models used in the "Technique" visual style (Simply Love Options > Visual Style > select "🌀") overlap with the notefield preview on SSMw.
We need to flush the z-buffer after drawing the Technique background models, regardless of the default, implied, or specified layering using draworder()

Jousway: I noticed that wiht fast note rendering on the def.notefields on the music wheel are broken, there is a way to fix this and @Mr. ThatKid does it in modifles, want him to show you how?
MrThatKid: Basically, you need a quad that clears the zbuffer.
So far, you've only got one BG that really needs this: Technique.lua (in _shared background)
And that should make your notefields not be cut into by that background. (And it did work on my end when I tried this) (the x(-1) is so you don't have a white pixel in the top left corner)
The reason this is needed is because many of the things in here are models, and they write to the zbuffer by default, so clearing it before we draw other things that can write to the zbuffer (eg: notefields with 3d noteskins) is a good idea
--]=====]

t[#t+1] = Def.Quad {
    InitCommand= function(self)
        self:x(-1):clearzbuffer(true)
    end
}

return t