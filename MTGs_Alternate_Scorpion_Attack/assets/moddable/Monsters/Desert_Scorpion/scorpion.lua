--[[
Copyright (c) 2020 Boris Marmontel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local MonsterFallState = require 'monster_fall_state'
local MonsterJumpState = require 'monster_jump_state'
local class = require 'middleclass'
local Monster = require 'monster_toolbox'
local MonsterLeaderEffect = require 'monster_leader_effect'
local Snapshot = require 'monster_snapshot_minimal'

local State = {
    Idle = 0,
    Wait = 1,
    Move = 2,
    GetHit = 3,
    Fall = 4,
    Getup = 5,
    Attack = 6,
    AttackDist = 7,
    JumpStart = 8,
    Jumping = 9,
    Dig = 10,
    Hidden = 11,
    TakeOut = 12,
    Die = 13
}

local Animations = {
    [State.Idle] = "idle",
    [State.Wait] = "idle",
    [State.Move] = "move",
    [State.GetHit] = "hit",
    [State.Fall] = "fall",
    [State.Getup] = "getup",
    [State.Attack] = "attack",
    [State.AttackDist] = "attack2",
    [State.JumpStart] = "move",
    [State.Jumping] = "move",
    [State.Dig] = "dig",
    [State.Hidden] = nil,
    [State.TakeOut] = "spawn",
    [State.Die] = "die"
}

local RenderConfig = Monster.initRenderConfigAttackAlt(
    "monster_scorpion",
    "pc_palette_monster_scorpion",
    State.AttackDist, true, 3, 13, false, "spit")

local rect = {
    Rect:new(0, 0, 28, 28),
    Rect:new(0, 0, 60, 60),
    Rect:new(0, 0, 76, 76)
}
local rect_hidden = {
    Rect:new(0, 27, 28, 28),
    Rect:new(0, 59, 60, 60),
    Rect:new(0, 75, 76, 76)
}

local SorpionBrainAI = class('SorpionBrainAI')
local MonsterSorpion = class('MonsterSorpion')

local gravity = MonsterJumpState.gravity

function MonsterSorpion:initialize()
    self.frame = 0.0
    self.state = State.Idle
    self.scalex = 1.0
    self.size = 0
    self.rect = rect[self.size+1]
    
    self.inputs = Input:new()
    self.inputs1 = 0
    self.inputs2 = 0
    self.bullet_launch = false
    
    self.jump_timer = 0.0
    self.long_jump = false
    self.ground_timer = 0.0
    
    self.attack_prepare = 0.0
    
    self.leader_effect = nil
    self.is_leader = false
    
    self.jump_state = MonsterJumpState:new(
        State.Idle, State.JumpStart, State.Jumping, 3.0,
        MonsterJumpState.twoFrameAnim(0,1))
    
    self.fall_state = MonsterFallState:new(
        State.Idle, State.GetHit, State.Fall, State.Getup,
        3,11,9, 3,4,5)
    
    self.prev_snap = Snapshot:new()
end

function MonsterSorpion:evCreate(entity, param)
    entity:setRenderBoxAuto(self.rect, -120, -64, 120, 0, self.size+1)
    
    if(param.special_spawn)
    then
        self.state = State.TakeOut
    end
    
    Monster.evCreate(self, entity, param, SorpionBrainAI)
    
    self.leader_effect = MonsterLeaderEffect:new(
        self.is_leader, State.Dig, State.Hidden, State.TakeOut)
    
    --entity:makeBrainKeyboard()
end

function MonsterSorpion:updateBbox()
    if(self.state == State.Hidden) then
        self.rect = rect_hidden[self.size+1]
    else
        self.rect = rect[self.size+1]
    end
end

function MonsterSorpion:setState(entity, state)
    self.state = state
    self.frame = 0.0
    
    if(self.state == State.Attack)
    then
        entity:soundPlay("attack", entity.pos)
    elseif(state == State.AttackDist)
    then
        self.attack_prepare = 20.0
        local box = entity:boundingBox()
        pcCreateAttackIcon(entity:getContext(), Vec2:new(box:center().x, box.y1 + 10))
    elseif(state == State.Hidden or state == State.TakeOut)
    then
        self:updateBbox()
    end
end

function MonsterSorpion:render(entity, r)
    Monster.render(self, entity, r, Animations, RenderConfig)
end

function MonsterSorpion:update(entity, dt)
    if(not entity:alive())
    then
        self.frame = self.frame + 0.22 * dt
        if(self.frame >= 10)
        then
            entity:instanceDestroy()
        else
            entity:updateLandPhysics(
                dt, 0.34, Vec2:new(), Vec2:new(0.05, 0.1), 4, true, false)
        end
        return
    end
    
    -- netplay client update
    if(entity:remote()) then
        local last_snap = Monster.netplayClientUpdate(self, entity)
        if(last_snap ~= nil) then
            if(self:shouldInflictDamages(self.state, self.frame)) then
                local hitbox = self:hitbox(self.state, entity)
                if(self.state == State.Attack) then
                    entity:inflictDamages(self.state, 0, self.scalex, -1, self.size/2.0 + 1)
                    self.bullet_launch = false
                elseif(self.state == State.AttackDist) then
                    MonsterSorpion:createProj(entity, self.bullet_launch ,self.scalex, entity:status());
                    self.bullet_launch = true
                end
            end
            self.bullet_launch = false
        end
        return
    end
    
    
    if(entity:isPetrified())
    then
        entity:updateLandPhysics(
            dt, 0.34, Vec2:new(), Vec2:new(0.05, 0.1), 4, true, false)
        return
    end
    
    entity:updateBrain(self.inputs, dt)
    self.inputs1 = bit32_bor(self.inputs1, self.inputs:state())
    self.inputs2 = bit32_bor(self.inputs2, self.inputs:ostate())
    
    -- Server
    local force = Vec2:new()
    local hspeed = 2.5
    
    local on_ground;
    on_ground, self.ground_timer =
        Monster.updateGroundTimer(entity, self.ground_timer, dt)
    
    self.fall_state:updateTimers(dt)
    
    if(self.attack_prepare > 0.0)
    then
        self.attack_prepare = self.attack_prepare - dt
        
        if(self.attack_prepare <= 0.0 and self.state == State.AttackDist)
        then
            entity:soundPlay("splat", entity.pos)
        end
    elseif(self.state == State.Idle)
    then
        self.frame = self.frame + 0.12 * dt
        
        if(on_ground)
        then
            if(self.inputs:check(InputKey.Space))
            then
                self:setState(entity, State.JumpStart)
            elseif(self.inputs:check(InputKey.MouseLeft))
            then
                if(self.inputs:check(InputKey.Down)) then
                    self:setState(entity, State.AttackDist)
                else
                    self:setState(entity, State.Attack)
                end
            elseif(Monster.checkMovementInput(self))
            then
                self:setState(entity, State.Move)
            elseif(self.inputs:check(InputKey.Action1)
                and entity:onDiggableGround())
            then
                self:setState(entity, State.Dig)
            end
        else
            self:setState(entity, State.Jumping)
        end
    elseif(self.state == State.Move)
    then
        self.frame = self.frame + 0.3 * dt
        
        if(on_ground)
        then
            if(self.inputs:check(InputKey.Space))
            then
                self:setState(entity, State.JumpStart)
            elseif(self.inputs:check(InputKey.MouseLeft))
            then
                if(self.inputs:check(InputKey.Down)) then
                    self:setState(entity, State.AttackDist)
                else
                    self:setState(entity, State.Attack)
                end
            elseif(self.inputs:check(InputKey.Action1)
                and entity:onDiggableGround())
            then
                self:setState(entity, State.Dig)
            elseif(Monster.checkMovementInput(self))
            then
                -- nop
            else
                self:setState(entity, State.Idle)
            end
            
            force.x = (hspeed + self.size/2.0) * entity:speedCoef() * self.scalex
        else
            self:setState(entity, State.Jumping)
        end
    end
    if(self.fall_state:update(self, entity, dt, 0.2, Vec2:new()))
    then
        -- nop
    elseif(self.jump_state:update(
        self, entity, self.inputs, entity.vel, self.scalex,
        force, hspeed + self.size/2.0, 0.3, dt))
    then
        -- nop
    elseif(self.state == State.Attack)
    then
        if(self.frame >= 3.0 and self.frame < 4.0)
        then
            self.frame = self.frame + 0.1 * dt
        else
            self.frame = self.frame + 0.2 * dt
        end
        
        if(self.frame > 4 and self.frame < 5) then
            entity:inflictDamages(self.state, 0, self.scalex, -1, self.size/2.0 + 1)
        end
        
        if(self.frame >= 8.0)
        then
            self:setState(entity, State.Idle)
        end
    elseif(self.state == State.AttackDist)
    then
        self.frame = self.frame + 0.2 * dt
        
        if(self.frame >= 5 and self.frame < 6) then
            MonsterSorpion:createProj(entity, self.bullet_launch ,self.scalex, entity:status())
            self.bullet_launch = true
        end
        
        if(self.frame >= 8.0)
        then
            self:setState(entity, State.Idle)
            self.bullet_launch = false
        end
    elseif(self.state == State.Dig)
    then
        self.frame = self.frame + 0.2 * dt
        if(self.frame >= 11.0)
        then
            if(self.inputs:check(InputKey.MouseLeft)
                and self.is_leader
                and not entity:isPlayerControlable())
            then
                -- TODO: "if less than 3 minions" ?
                -- smallest mask is required for createMinions
                self.rect = rect[1]
                self.leader_effect:createMinions(self, entity)
            end
            -- self.rect is set to rect_hidden here
            self:setState(entity, State.Hidden)
        end
    elseif(self.state == State.Hidden)
    then
        self.frame = self.frame + dt
        
        if(self.is_leader) then
            if(not self.leader_effect:waitUntilMinionsAreDead(self, entity)) then
                self:setState(entity, State.TakeOut)
            end
        elseif(self.inputs:check(InputKey.Space) or self.frame >= 3 * 60.0)
        then
            self:setState(entity, State.TakeOut)
            
            if(not entity:isPlayerControlable()) then
                -- Respawn at a random possible location
                local cells = entity:findNearbySpawnsOnDiggableGround(22,10)
                if(#cells > 0) then
                    local cell = cells[ math.random(#cells) ]
                    entity.pos = cell:coords()
                    entity.pos.y = entity.pos.y - self:bbox():height() + 16
                end
            end
        end
    elseif(self.state == State.TakeOut)
    then
        self.frame = self.frame + 0.15 * dt
        if(self.frame >= 9.0)
        then
            self:setState(entity, State.Idle)
        end
    end
    
    local platforms_solid = not self.inputs:check(InputKey.Control)
    entity:enablePlatforms(platforms_solid)
    entity:updateLandPhysics(
        dt, gravity, force, Vec2:new(0.05,0), 0.2, true,
        self.fall_state:canBounce(self))
    entity:enablePlatforms(false)
end

function MonsterSorpion:hitbox(state, entity)
    local box = {}
    local anchor_x = -self.scalex
    
    if(state == State.Attack)
    then
        box = entity:boundingBoxRelative()
        box:scale(1.5, 1.0, anchor_x, RectAnchor.Bottom)
        box:translate(entity.pos.x + 18*self.scalex*(self.size+1), entity.pos.y)
    else
        box = Rect:new()
    end
    
    return box
end

function MonsterSorpion:evHurt(entity, damages, owner)
    if(self.state ~= State.Hidden)
    then
        if(not self.fall_state:hurt(self, entity, damages))
        then
            local dmg = damages:clone()
            dmg.force = HitForce:new()
            return entity:hurtBase(dmg, owner)
        end
        return entity:hurtBase(damages, owner)
    end
    return Hit:new(HitType.NoContact)
end

function MonsterSorpion:evGetHit(entity, owner, damages)
    entity:evGetHitBase(owner, damages)
    
    if(entity:alive()) then
        entity:soundPlay("hurt", entity.pos)
    end
end


function MonsterSorpion:createProj(entity, bullet_launch ,_scalex, status)
    if (bullet_launch == true) then
        return
    end
    
    
    local scalex = _scalex or 1
    
    local box = entity:boundingBox()
    local pos = Vec2:new(box.x2 + 6 * scalex, box.y1 - 20)
    local angle = scalex < 0 and 180 or 0
    
    local spell = pcGenerateSpell(
        pcEntryIdFromString("scorpion_proj"),
        entity:attribs().level,
        entity:targetType())
        
        
                
    if status:findEffect(StatusEffectType.Giant) then
        spell = pcGenerateSpell(
            pcEntryIdFromString("scorpion_proj_big"),
            entity:attribs().level,
            entity:targetType())

    end
        
    pcCreateSpellSimple(
        entity:getContext(), spell, pos, angle,
        0) -- burst index, 0 = first
end

function MonsterSorpion:evDie(entity, owner)
    entity:evDieBase(owner)
    self.frame = 0
    self.state = State.Die
    entity:soundPlay("die", entity.pos)
end

function MonsterSorpion:makeBrain(entity)
    return SorpionBrainAI:new()
end

function MonsterSorpion:haveRecoil(entity)
    return true
end

function MonsterSorpion:bbox()
    return self.rect
end

function MonsterSorpion:facingx()
    return self.scalex
end

function MonsterSorpion:isIdle()
    return self.state == State.Idle
end

function MonsterSorpion:isMoving()
    return self.state == State.Move
end

function MonsterSorpion:isJumping()
    return self.state == State.Jumping
end

function MonsterSorpion:isFalling()
    return self.state == State.Fall
end

function MonsterSorpion:canBeUsedAsMount(entity)
    return false
end

function MonsterSorpion:drawLife(entity)
    if(self.state == State.Hidden or self.state == State.TakeOut) then
        return false
    else
        return entity:drawLife()
    end
end

function MonsterSorpion:shouldInflictDamages(state, frame)
    return ((state == State.Attack and frame >= 4 and frame < 5) or
            (state == State.AttackDist and frame >= 6 and frame < 7));
end

-- Netplay deprecated

function MonsterSorpion:evSend(entity, buf)
    Monster.evSend(self, entity, buf, 0x00)
end

function MonsterSorpion:evReceive(entity, buf)
    Monster.evReceive(self, entity, buf)
end

-- Netplay

function MonsterSorpion:evSendReliable(entity, buf)
    Monster.evSendReliable(Snapshot, self, entity, buf)
end

function MonsterSorpion:evReceiveReliable(entity, buf)
    Monster.evReceiveReliable(Snapshot, entity, buf)
end


-- AI

function SorpionBrainAI:initialize()
    self.cooldown = 0.0
    self.invoke_cooldown = 0.0
    self.hide_cooldown = 0.0
end

function SorpionBrainAI:update(m, entity, brain, inputs, dt)
    self.cooldown = self.cooldown - dt
    brain:updateAI(entity, inputs, dt)
    
    if(m.is_leader)
    then
        self.invoke_cooldown = self.invoke_cooldown - dt
        self.hide_cooldown = self.hide_cooldown - dt
        
        if(self.invoke_cooldown <= 0.0)
        then
            if(m.state == State.TakeOut)
            then
                self.invoke_cooldown = 60.0 * 30
            elseif(m.state == State.Dig)
            then
                inputs:simulateCheck(InputKey.MouseLeft)
            else
                inputs:simulateCheck(InputKey.Action1)
            end
        elseif(self.hide_cooldown <= 0.0)
        then
            if(m.state == State.Hidden)
            then
                self.hide_cooldown = 60.0 * 5
                inputs:simulateCheck(InputKey.Space)
            elseif(m.state ~= State.Dig)
            then
                inputs:simulateCheck(InputKey.Action1)
            end
        end
    end
end

function SorpionBrainAI:tryToAttack(m, entity, focus, inputs)
    local dist = focus:distanceTo(entity:asAliveEntity())
    local facing = false
    local expert = 0
    
    local box1 = entity:boundingBox()
    local box2 = focus.box
    
    if(m:facingx() > 0.0)
    then
        facing = (box1.x2 <= box2.x1)
    else
        facing = (box1.x1 >= box2.x2)
    end

    local vsep = math.abs(box1:center().y - box2:center().y)
    local scale = m.size + 1

    if(facing and focus:canBeHit(m:hitbox(State.Attack, entity)))
    then
        inputs:simulateCheck(InputKey.MouseLeft)
        return true
    elseif(self.cooldown <= 0
         and facing)
    then
        inputs:simulateCheck(InputKey.MouseLeft)
        inputs:simulateCheck(InputKey.Down)
        self.cooldown = 600
        return true
    elseif(facing
        and dist < 160 * scale
        and vsep < 32 * scale
        and math.random() < 0.005 * (1 + expert*10))
    then
        inputs:simulateCheck(InputKey.Space)
        inputs:simulateCheck(InputKey.Shift)
        return true
    end

    return false
end


return MonsterSorpion


