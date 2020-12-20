local folderName = ...

---------------
-- LIBRARIES --
---------------
local AceAddon = LibStub("AceAddon-3.0")
local LibCamera = LibStub("LibCamera-1.0")
local LibEasing = LibStub("LibEasing-1.0")


---------------
-- CONSTANTS --
---------------

-- The transition time of SetView() is hard to predict.
-- Use this for now.
local SET_VIEW_TRANSITION_TIME = 0.5


-------------
-- GLOBALS --
-------------
DynamicCam = AceAddon:NewAddon(folderName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")


DynamicCam.currentSituationID = nil


-- This flag is to activate the shoulderOffsetEasingFrame (see below).
-- Furthermore, the info may be needed by CameraOverShoulderFix, such that it does not interfere.
DynamicCam.easeShoulderOffsetInProgress = false


-- Needed by CameraOverShoulderFix to know if a zoom easing is in progress.
DynamicCam.LibCamera = LibCamera

-- To allow zooming during shoulder offset easing, we must store the current
-- shoulder offset in a global variable that is changed by the easing process
-- and taken into account by the zoom functions.
-- This is also needed by CameraOverShoulderFix because when mounted, the compensation
-- factor depends on whether the shoulder offset is positive or negative.
DynamicCam.currentShoulderOffset = 0

------------
-- LOCALS --
------------
local _
local Options
local functionCache = {}
local situationEnvironments = {}
local conditionExecutionCache = {}



local OldCameraZoomIn = CameraZoomIn
local OldCameraZoomOut = CameraZoomOut



-- The mimimal third person zoom value depends on the current model.
local minZoomMounted = 1.5

local modelFrame = CreateFrame("PlayerModel")
local function GetModelId()
    modelFrame:SetUnit("player")
    return modelFrame:GetModelFileID()
end
local function GetMinZoom()
  if IsMounted() then
    return minZoomMounted
  else
    return minZoomValues[GetModelId()]
  end
end

-- Set to true when zooming out from first person, such that the next zoom is stored as min value.
local storeMinZoom = false


-- To indicate if a non-reactive zoom is in progress.
local nonReactiveZoomStarted = false
local nonReactiveZoomInProgress = false
local nonReactiveZoomStartValue = GetCameraZoom()



-- We have to be able to set this to nil whenever
-- SetZoom() or SetView() happens. Otherwise, the
-- next scroll wheel turn will scroll back
-- to the last zoom position.
local reactiveZoomTarget = nil


-- When SetView() happens, the zoom level of the new view is
-- returned instantaneously by GetCameraZoom().
-- If "Adjust Shoulder offset according to zoom level" is activated,
-- this may lead to a shoulder offset skip. Thus we have to make
-- a virtual zoom ease for SET_VIEW_TRANSITION_TIME on this variable:
local virtualCameraZoom = nil


-- To evaluate situations one frame after an event is triggered
-- (see EventHandler() and ShoulderOffsetEasingFunction()).
local evaluateSituationsNextFrame = false


-- Forward declaration.
local UpdateCurrentShoulderOffset
local SetCorrectedShoulderOffset


-- We use this to suppress situation entering easing at login!
local enteredSituationAtLogin = false

-- Use this variable to get the duration of the last frame, to determine if easing is worthwhile.
-- This is more accurate than the game framerate, which is the average over several recent frames.
local secondsPerFrame = 1.0/GetFramerate()



-- For other Addons (like Narcissus) to temporarily disable
-- "Adjust Shoulder offset according to zoom level" without
-- having to change the user's permanent DynamicCam profile.
local shoulderOffsetZoomTmpDisable = false
function DynamicCam:BlockShoulderOffsetZoom()
  shoulderOffsetZoomTmpDisable = true
end
function DynamicCam:AllowShoulderOffsetZoom()
  shoulderOffsetZoomTmpDisable = false
end



-- This frame continuously applies the new shoulder offset while easing of zoom or shoulder offset is in progress.
-- The easing functions just modify the zoom or currentShoulderOffset which are taken
-- into account here.
local function ShoulderOffsetEasingFunction(self, elapsed)

    -- Also using this frame also to log secondsPerFrame,
    -- which we need below to determine if easing is worthwhile.
    secondsPerFrame = elapsed

    -- Also using the frame to evaluate situations one frame after an event
    -- is triggered (see EventHandler()). This way we are never too early.
    if evaluateSituationsNextFrame then
        evaluateSituationsNextFrame = false
        DynamicCam:EvaluateSituations()
    end

    -- When we are going into a view, the zoom level of the new view is returned
    -- by GetCameraZoom() immediately. Hence, we have to simulate a "virtual"
    -- camera zoom easing for SET_VIEW_TRANSITION_TIME.
    local cameraZoom
    if virtualCameraZoom ~= nil then
        cameraZoom = virtualCameraZoom
    else
        cameraZoom = GetCameraZoom()
    end
    SetCorrectedShoulderOffset(cameraZoom)

end
local shoulderOffsetEasingFrame = CreateFrame("Frame")
shoulderOffsetEasingFrame:SetScript("onUpdate", ShoulderOffsetEasingFunction)




local function DC_RunScript(script, situationID)
    if not script or script == "" then
        return
    end

    -- make sure that we're not creating tables willy nilly
    if not functionCache[script] then
        functionCache[script] = assert(loadstring(script))

        -- if env, set the environment to that
        if situationID then
            if not situationEnvironments[situationID] then
                situationEnvironments[situationID] = setmetatable({}, { __index =
                    function(t, k)
                        if k == "_G" then
                            return t
                        elseif k == "this" then
                            return situationEnvironments[situationID].this
                        else
                            return _G[k]
                        end
                    end
                })
                situationEnvironments[situationID].this = {}
            end

            setfenv(functionCache[script], situationEnvironments[situationID])
        end
    end

    -- return the result
    return functionCache[script]()
end

local function DC_SetCVar(cvar, setting)

    if cvar == "test_cameraOverShoulder" then
        -- print("test_cameraOverShoulder", setting)

        UpdateCurrentShoulderOffset(setting)
        if not LibCamera:IsZooming() and not DynamicCam.easeShoulderOffsetInProgress then
            SetCorrectedShoulderOffset(GetCameraZoom())
        end

    -- don't apply cvars if they're already set to the new value
    elseif GetCVar(cvar) ~= tostring(setting) then
        -- print(cvar, setting)
        SetCVar(cvar, setting)
    end
end

local function round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

local function gotoView(view, instant)
    -- print("gotoView", view, instant)

    -- View change overrides all zooming.
    LibCamera:StopZooming()

    -- Whenever the zoom changes we need to reset the reactiveZoomTarget.
    reactiveZoomTarget = nil


    local cameraZoomBefore = GetCameraZoom()

    -- if you call SetView twice, then it's instant
    if instant then
        SetView(view)
    end
    SetView(view)

    local cameraZoomAfter = GetCameraZoom()
    -- print("Going from", cameraZoomBefore, "to", cameraZoomAfter)

    -- If "Adjust Shoulder offset according to zoom level" is activated,
    -- the shoulder offset will be instantaneously set according to the new
    -- camera zoom level. However, we should instead ease it for SET_VIEW_TRANSITION_TIME.
    if DynamicCam.db.profile.shoulderOffsetZoom.enabled and not shoulderOffsetZoomTmpDisable then
        DynamicCam.easeShoulderOffsetInProgress = true
        virtualCameraZoom = cameraZoomBefore

        LibEasing:Ease(
            function(newValue)
                virtualCameraZoom = newValue
            end,
            cameraZoomBefore,
            cameraZoomAfter,
            SET_VIEW_TRANSITION_TIME,
            LibEasing.Linear,
            function()
                DynamicCam.easeShoulderOffsetInProgress = false
                virtualCameraZoom = nil
            end
        )
    end
end

local function copyTable(originalTable)
    local origType = type(originalTable)
    local copy
    if origType == 'table' then
        -- this child is a table, copy the table recursively
        copy = {}
        for orig_key, orig_value in next, originalTable, nil do
            copy[copyTable(orig_key)] = copyTable(orig_value)
        end
    else
        -- this child is a value, copy it cover
        copy = originalTable
    end
    return copy
end


----------------------
-- SHOULDER OFFSET  --
----------------------

-- For zoom levels smaller than finishDecrease, we already want a shoulder offset of 0.
-- For zoom levels greater than startDecrease, we want the user set shoulder offset.
-- For zoom levels in between, we want a gradual transition between the two above.
-- We also need access to this function for CameraOverShoulderFix.
function DynamicCam:GetShoulderOffsetZoomFactor(zoomLevel)
    -- print("GetShoulderOffsetZoomFactor(" .. zoomLevel .. ")")

    if not DynamicCam.db.profile.shoulderOffsetZoom.enabled or shoulderOffsetZoomTmpDisable then
        return 1
    end

    local startDecrease = DynamicCam.db.profile.shoulderOffsetZoom.upperBound
    local finishDecrease = DynamicCam.db.profile.shoulderOffsetZoom.lowerBound

    local zoomFactor = 1
    if zoomLevel < finishDecrease then
        zoomFactor = 0
    elseif zoomLevel < startDecrease then
        zoomFactor = (zoomLevel-finishDecrease) / (startDecrease-finishDecrease)
    end

    -- print("zoomFactor:", zoomFactor)
    return zoomFactor
end


-- Forward declaration above...
SetCorrectedShoulderOffset = function(cameraZoom)
    local correctedShoulderOffset = DynamicCam.currentShoulderOffset * DynamicCam:GetShoulderOffsetZoomFactor(cameraZoom)
    if cosFix then
        if not cosFix.currentModelFactor then
            cosFix.currentModelFactor = cosFix:CorrectShoulderOffset()
        end
        correctedShoulderOffset = correctedShoulderOffset * cosFix.currentModelFactor
    end

    correctedShoulderOffset = round(correctedShoulderOffset, 10)
    if tonumber(GetCVar("test_cameraOverShoulder")) ~= correctedShoulderOffset then
        -- print("SetCVar test_cameraOverShoulder", correctedShoulderOffset)
        SetCVar("test_cameraOverShoulder", correctedShoulderOffset)
    end
end

-- Forward declaration above...
UpdateCurrentShoulderOffset = function(offset)
    -- print("UpdateCurrentShoulderOffset", offset)

    -- If offset changes sign while mounted, CameraOverShoulderFix needs to update currentModelFactor!
    if cosFix and IsMounted() then
        if (DynamicCam.currentShoulderOffset < 0 and offset >= 0)
        or (DynamicCam.currentShoulderOffset >= 0 and offset < 0) then
            cosFix.currentModelFactor = cosFix:CorrectShoulderOffset()
        end
    end

    DynamicCam.currentShoulderOffset = offset
end


local easeShoulderOffsetHandle
local function StopEasingShoulderOffset()
    DynamicCam.easeShoulderOffsetInProgress = false
    if easeShoulderOffsetHandle then
        LibEasing:StopEasing(easeShoulderOffsetHandle)
        easeShoulderOffsetHandle = nil
    end
end

local function EaseShoulderOffset(newValue, duration, easingFunc, callback)
    -- print("EaseShoulderOffset", DynamicCam.currentShoulderOffset, "->", newValue, duration)

    StopEasingShoulderOffset()

    -- When the duration is 0, the easeShoulderOffsetInProgress = false callback will
    -- be called before shoulderOffsetEasingFrame can set the new value. So we do it here!
    -- A return below will happen, because UpdateCurrentShoulderOffset sets currentShoulderOffset = newVale.
    if duration == 0 then
        UpdateCurrentShoulderOffset(newValue)
        SetCorrectedShoulderOffset(GetCameraZoom())
    end

    if DynamicCam.currentShoulderOffset == newValue then
        if callback then
            return callback()
        else
            return
        end
    end

    -- Store that we are currently easing, such that CameraOverShoulderFix does not
    -- change the shoulder offset prematurely. It then only sets currentModelFactor
    -- to the new value while the easing is going on.
    DynamicCam.easeShoulderOffsetInProgress = true

    easeShoulderOffsetHandle = LibEasing:Ease(
        UpdateCurrentShoulderOffset,
        DynamicCam.currentShoulderOffset,
        newValue,
        duration,
        easingFunc,
        function()
            DynamicCam.easeShoulderOffsetInProgress = false
            if callback then
                callback()
            end
        end
    )
end




-------------
-- FADE UI --
-------------
local easeUIAlphaHandle
local hidMinimap
local unfadeUIFrame = CreateFrame("Frame", "DynamicCamUnfadeUIFrame")
local combatSecureFrame = CreateFrame("Frame", "DynamicCamCombatSecureFrame", nil, "SecureHandlerStateTemplate")
combatSecureFrame.hidUI = nil
combatSecureFrame.lastUIAlpha = nil

RegisterStateDriver(combatSecureFrame, "dc_combat_state", "[combat] combat; [nocombat] nocombat")
combatSecureFrame:SetAttribute("_onstate-dc_combat_state", [[ -- arguments: self, stateid, newstate
    if newstate == "combat" then
        if self.hidUI then
            setUIAlpha(self.lastUIAlpha)
            UIParent:Show()

            self.lastUIAlpha = nil
            self.hidUI = nil
        end
    end
]])

local function setUIAlpha(newAlpha)
    if newAlpha and type(newAlpha) == 'number' then
        UIParent:SetAlpha(newAlpha)

        -- show unfadeUIFrame if we're faded
        if newAlpha < 1 and not unfadeUIFrame:IsShown() then
            unfadeUIFrame:Show()
        elseif newAlpha == 1 then
            -- UI is no longer faded, remove the esc handler
            if unfadeUIFrame:IsShown() then
                -- want to hide the frame without calling it's onhide handler
                local onHide = unfadeUIFrame:GetScript("OnHide")
                unfadeUIFrame:SetScript("OnHide", nil)
                unfadeUIFrame:Hide()
                unfadeUIFrame:SetScript("OnHide", onHide)
            end
        end
    end
end

local function stopEasingUIAlpha()
    -- if we are currently easing the UI out, make sure to stop that
    if easeUIAlphaHandle then
        LibEasing:StopEasing(easeUIAlphaHandle)
        easeUIAlphaHandle = nil
    end

    -- show the minimap if we hid it and it's still hidden
    if hidMinimap and not Minimap:IsShown() then
        Minimap:Show()
        hidMinimap = nil
    end

    -- show the UI if we hid it and it's still hidden
    if combatSecureFrame.hidUI then
        if not UIParent:IsShown() and (not InCombatLockdown() or issecure()) then
            setUIAlpha(combatSecureFrame.lastUIAlpha)
            UIParent:Show()
        end

        combatSecureFrame.hidUI = nil
        combatSecureFrame.lastUIAlpha = nil
    end
end

local function easeUIAlpha(endValue, duration, easingFunc, callback)
    stopEasingUIAlpha()

    if UIParent:GetAlpha() ~= endValue then
        easeUIAlphaHandle = LibEasing:Ease(setUIAlpha, UIParent:GetAlpha(), endValue, duration, easingFunc, callback)
    else
        -- we're not going to ease because we're already there, have to call the callback anyways
        if callback then
            callback()
        end
    end
end

local function fadeUI(situationExtras, duration)

    local opacity = situationExtras.hideUIFadeOpacity
    local hideUI = situationExtras.actuallyHideUI
    local keepMinimap = situationExtras.keepMinimap

    -- setup a callback that will hide the UI if given or hide the minimap if opacity is 0
    local callback = function()
        if opacity > 0 then return end

        if hideUI and UIParent:IsShown() and (not InCombatLockdown() or issecure()) then
            -- hide the UI, but make sure to make opacity 1 so that if escape is pressed, it is shown
            setUIAlpha(1)
            UIParent:Hide()

            combatSecureFrame.lastUIAlpha = opacity
            combatSecureFrame.hidUI = true
        elseif not keepMinimap and Minimap:IsShown() then
            -- hide the minimap
            Minimap:Hide()
            hidMinimap = true
        end
    end

    if keepMinimap then
        MinimapCluster:SetIgnoreParentAlpha(true)
    end

    easeUIAlpha(opacity, duration, nil, callback)
end

local function unfadeUI(opacity, duration)
    stopEasingUIAlpha()
    easeUIAlpha(opacity, duration, nil, function() MinimapCluster:SetIgnoreParentAlpha(false) end)
end

-- need to be able to clear the faded UI, use dummy frame that Show() on fade, which will cause esc to
-- hide it, make OnHide
unfadeUIFrame:SetScript("OnHide", function(self)
    stopEasingUIAlpha()
    UIParent:SetAlpha(1)
end)
tinsert(UISpecialFrames, unfadeUIFrame:GetName())



----------
-- CORE --
----------
local started
local events = {}

function DynamicCam:OnInitialize()
    -- setup db
    self:InitDatabase()
    self:RefreshConfig()

    -- setup chat commands
    self:RegisterChatCommand("dynamiccam", "OpenMenu")
    self:RegisterChatCommand("dc", "OpenMenu")

    self:RegisterChatCommand("saveview", "SaveViewCC")
    self:RegisterChatCommand("sv", "SaveViewCC")

    self:RegisterChatCommand("zoominfo", "ZoomInfoCC")
    self:RegisterChatCommand("zi", "ZoomInfoCC")

    self:RegisterChatCommand("zoom", "ZoomSlash")
    self:RegisterChatCommand("pitch", "PitchSlash")
    self:RegisterChatCommand("yaw", "YawSlash")

    -- Disable the ActionCam warning message.
    UIParent:UnregisterEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")


    -- The real minimal zoom values are kept in a SaveVariable.
    if not minZoomValues then
        minZoomValues = {}
    end

end

function DynamicCam:OnEnable()
    self:Startup()
end

function DynamicCam:OnDisable()
    self:Shutdown()
end

function DynamicCam:Startup()
    -- make sure that shortcuts have values
    if not Options then
        Options = self.Options
    end

    -- register for dynamiccam messages
    self:RegisterMessage("DC_SITUATION_ENABLED")
    self:RegisterMessage("DC_SITUATION_DISABLED")
    self:RegisterMessage("DC_SITUATION_UPDATED")
    self:RegisterMessage("DC_BASE_CAMERA_UPDATED")

    -- initial evaluate needs to be delayed because the camera doesn't like changing cvars on startup
    self:ScheduleTimer("ApplyDefaultCameraSettings", 0.1)
    self:ScheduleTimer("EvaluateSituations", 0.2)
    self:ScheduleTimer("RegisterEvents", 0.3)

    -- turn on reactive zoom if it's enabled
    if self.db.profile.reactiveZoom.enabled then
        self:ReactiveZoomOn()
    else
        -- Must call this to prehook NonReactiveZoomIn/Out.
        self:ReactiveZoomOff()
    end

    started = true

    enteredSituationAtLogin = false


    SetCVar("CameraKeepCharacterCentered", 0)


    -- For coding
    -- C_Timer.After(0, self.OpenMenu)

end

function DynamicCam:Shutdown()

    -- exit the current situation if in one
    if self.currentSituationID then
        self:ChangeSituation(self.currentSituationID, nil)
    end

    events = {}
    self:UnregisterAllEvents()
    self:UnregisterAllMessages()

    -- apply default settings
    self:ApplyDefaultCameraSettings()

    -- turn off reactiveZoom
    self:ReactiveZoomOff()

    started = false
end

-- function DynamicCam:DebugPrint(...)
    -- if self.db.profile.debugMode then
        -- self:Print(...)
    -- end
-- end


----------------
-- SITUATIONS --
----------------
local delayTime
local delayTimer


-- To store the last zoom when leaving a situation.
local lastZoom = {}
-- To store the previous situation when entering another situation.
local lastSituation = {}
-- Depending on the "Restore Zoom" setting, a user may want to always restore
-- the last zoom when returning to a previous situation. Only for the "adaptive"
-- setting (which is actually the original way DynamicCam did it) we also have
-- to remember the last situation, because we only restore the zoom when returning
-- to the same situation we came from.


function DynamicCam:EvaluateSituations()

    -- print("EvaluateSituations", enteredSituationAtLogin, GetTime())

    local highestPriority = -100
    local topSituation

    -- go through all situations pick the best one
    for id, situation in pairs(self.db.profile.situations) do
        if situation.enabled then
            -- evaluate the condition, if it checks out and the priority is larger than any other, set it
            local lastEvaluate = conditionExecutionCache[id]
            local thisEvaluate = DC_RunScript(situation.condition, id)
            conditionExecutionCache[id] = thisEvaluate

            if thisEvaluate then
                -- the condition is true
                if not lastEvaluate then
                    -- last evaluate wasn't true, so this we "flipped"
                    self:SendMessage("DC_SITUATION_ACTIVE", id)
                end

                -- check to see if we've already found something with higher priority
                if situation.priority > highestPriority then
                    highestPriority = situation.priority
                    topSituation = id
                end
            else
                -- the condition is false
                if lastEvaluate then
                    -- last evaluate was true, so we "flipped"
                    self:SendMessage("DC_SITUATION_INACTIVE", id)
                end
            end
        end
    end

    local swap = true
    if self.currentSituationID and (not topSituation or topSituation ~= self.currentSituationID) then
        -- we're in a situation that isn't the topSituation or there is no topSituation
        local delay = self.db.profile.situations[self.currentSituationID].delay
        if delay > 0 then
            if not delayTime then
                -- not yet cooling down, make sure to guarentee an evaluate, don't swap
                delayTime = GetTime() + delay
                delayTimer = self:ScheduleTimer("EvaluateSituations", delay, "DELAY_TIMER")
                -- print("Not changing situation because of a delay")
                swap = false
            elseif delayTime > GetTime() then
                -- still cooling down, don't swap
                swap = false
            end
        end
    end

    if swap then
        if topSituation then
            if topSituation ~= self.currentSituationID then
                -- we want to swap and there is a situation to swap into, and it's not the current situation
                self:ChangeSituation(self.currentSituationID, topSituation)
            end

            -- if we had a delay previously, make sure to reset it
            delayTime = nil
        else
            --none of the situations are active, leave the current situation
            if self.currentSituationID then
                self:ChangeSituation(self.currentSituationID, nil)
            end
        end
    end


    enteredSituationAtLogin = true

    -- print("Finished EvaluateSituations", enteredSituationAtLogin, GetTime())
end


-- Start rotating when entering a situation.
function DynamicCam:StartRotation(newSituation, transitionTime)
    local a = newSituation.cameraActions
    if a.rotate then
        if a.rotateSetting == "continuous" then
            LibCamera:BeginContinuousYaw(a.rotateSpeed, transitionTime)
        elseif a.rotateSetting == "degrees" then
            if a.yawDegrees ~= 0 then
                LibCamera:Yaw(a.yawDegrees, transitionTime, LibEasing[self.db.profile.easingYaw])
            end

            if a.pitchDegrees ~= 0 then
                LibCamera:Pitch(a.pitchDegrees, transitionTime, LibEasing[self.db.profile.easingPitch])
            end
        end
    end
end

-- Stop rotating when leaving a situation.
function DynamicCam:StopRotation(oldSituation)
    local a = oldSituation.cameraActions
    if a.rotate then
        if a.rotateSetting == "continuous" then
            local yaw = LibCamera:StopYawing()

            -- rotate back if we want to
            if a.rotateBack then
                -- print("Ended rotate, degrees rotated, yaw:", yaw)
                if yaw then
                    local yawBack = yaw % 360

                    -- we're beyond 180 degrees, go the other way
                    if yawBack > 180 then
                        yawBack = yawBack - 360
                    end

                    LibCamera:Yaw(-yawBack, 0.75, LibEasing[self.db.profile.easingYaw])
                end
            end
        elseif a.rotateSetting == "degrees" then
            if LibCamera:IsRotating() then
                -- interrupted rotation
                local yaw, pitch = LibCamera:StopRotating()

                -- rotate back if we want to
                if a.rotateBack then
                    -- print("Ended rotate early, degrees rotated, yaw:", yaw, "pitch:", pitch)
                    if yaw then
                        LibCamera:Yaw(-yaw, 0.75, LibEasing[self.db.profile.easingYaw])
                    end

                    if pitch then
                        LibCamera:Pitch(-pitch, 0.75, LibEasing[self.db.profile.easingPitch])
                    end
                end
            else
                if a.rotateBack then
                    if a.yawDegrees ~= 0 then
                        LibCamera:Yaw(-a.yawDegrees, 0.75, LibEasing[self.db.profile.easingYaw])
                    end

                    if a.pitchDegrees ~= 0 then
                        LibCamera:Pitch(-a.pitchDegrees, 0.75, LibEasing[self.db.profile.easingPitch])
                    end
                end
            end
        end
    end
end



function DynamicCam:ChangeSituation(oldSituationID, newSituationID)

    -- print("ChangeSituation", oldSituationID, newSituationID, GetTime())

    LibCamera:StopZooming()


    -- When we are storing or setting a view, we shall not apply any zoom.
    -- Restoring a view shall have higher priority than setting a new one.
    -- We need to differentiate between the two to know which "instant" to take
    -- into account below.
    local restoringView = false
    local settingView = false


    -- Needed so often that we are setting these shortcuts for the whole function scope.
    local oldSituation
    local newSituation



    -- If we are exiting another situation.
    if oldSituationID then
        -- Store last zoom level of this situation.
        lastZoom[oldSituationID] = GetCameraZoom()
        -- print("---> Storing zoom", lastZoom[oldSituationID], oldSituationID)


        oldSituation = self.db.profile.situations[oldSituationID]

        -- Stop rotating if applicable.
        self:StopRotation(oldSituation)

        -- Restore view if applicable.
        if oldSituation.view.enabled and oldSituation.view.restoreView then
            gotoView(1, oldSituation.view.instant)
            restoringView = true
        end

        -- Load and run advanced script onExit.
        DC_RunScript(oldSituation.executeOnExit, oldSituationID)

        -- Unhide UI if applicable.
        if oldSituation.extras.hideUI then
            -- Use default transition time for UI fade.
            unfadeUI(1, 0.5)
        end

        self:SendMessage("DC_SITUATION_EXITED")


    -- If we are coming from the no-situation state.
    elseif enteredSituationAtLogin then
        lastZoom["default"] = GetCameraZoom()
        -- print("---> Storing default zoom", lastZoom[oldSituationID], oldSituationID)
    end



    -- If we are entering a new situation.
    if newSituationID then
        -- Store the old situation as the new situation's last situation.
        -- May also be nil in case of coming from the no-situation state.
        -- (Needed for "adaptive restore", where we only restore when
        -- returning to the same situation we came from.)
        lastSituation[newSituationID] = oldSituationID

        newSituation = self.db.profile.situations[newSituationID]

        -- Set view settings
        -- (Restoring a view has a higher priority than setting a new one.)
        if newSituation.view.enabled and not restoringView then
            if newSituation.view.restoreView then SaveView(1) end
            gotoView(newSituation.view.viewNumber, newSituation.view.instant)
            settingView = true
        end

        -- Load and run advanced script onEnter.
        DC_RunScript(newSituation.executeOnEnter, newSituationID)

        -- Hide UI if applicable.
        if newSituation.extras.hideUI then
            -- Use default transition time for UI fade.
            fadeUI(newSituation.extras, 0.5)
        end


    -- If we are entering the no-situation state.
    -- else

    end



    -- These values are needed for the actual transition.
    local newZoomLevel
    local newShoulderOffset
    local transitionTime


    -- ##### Determine newZoomLevel. #####
    newZoomLevel = GetCameraZoom()

    -- We only need to determine newZoomLevel if we are zooming.
    if not restoringView and not settingView then

        -- Check if we should restore a stored zoom level.
        local shouldRestore, zoomLevel = self:ShouldRestoreZoom(oldSituationID, newSituationID)
        if shouldRestore then
            newZoomLevel = zoomLevel

        -- Otherwise take the zoom level of the situation we are entering.
        -- (There is no default zoom level for the no-situation case!)
        elseif newSituationID then

            local a = newSituation.cameraActions

            if (a.zoomSetting == "set") or
               (a.zoomSetting == "in"  and newZoomLevel > a.zoomValue) or
               (a.zoomSetting == "out" and newZoomLevel < a.zoomValue) then

                newZoomLevel = a.zoomValue

            elseif a.zoomSetting == "range" then
                if newZoomLevel < a.zoomMin then
                    newZoomLevel = a.zoomMin
                elseif newZoomLevel > a.zoomMax then
                    newZoomLevel = a.zoomMax
                end
            end
        end
    end



    -- ##### Determine newShoulderOffset. #####
    if newSituation and newSituation.cameraCVars.test_cameraOverShoulder then
        newShoulderOffset = newSituation.cameraCVars.test_cameraOverShoulder
    else
        newShoulderOffset = self.db.profile.standardCvars.test_cameraOverShoulder
    end



    -- ##### Determine transitionTime. #####

    -- After reloading the UI we want to enter the current situation immediately!
    if not enteredSituationAtLogin then
        transitionTime = 0

    -- If there is a transitionTime in the environment, it has maximum priority.
    elseif newSituationID and situationEnvironments[newSituationID].this.transitionTime then
        transitionTime = situationEnvironments[newSituationID].this.transitionTime

    -- When restoring or setting a view, there is no additional zoom.
    -- The shoulder offset transition should be as fast at the view change.
    -- 0.5 seems to be good for non-instant gotoView.
    -- Restoring a stored view has a greater priority than than setting a new view.
    elseif restoringView then
        -- If restoringView is true, we know there must be an oldSituationID.
        if self.db.profile.situations[oldSituationID].view.instant then
            transitionTime = 0
        else
            transitionTime = SET_VIEW_TRANSITION_TIME
        end
    elseif settingView then
        -- If settingView is true, we know there must be a newSituationID.
        if newSituation.view.instant then
            transitionTime = 0
        else
            transitionTime = SET_VIEW_TRANSITION_TIME
        end

    -- Otherwise the new situation's transition time is taken.
    elseif newSituation and newSituation.cameraActions.transitionTime then
        transitionTime = newSituation.cameraActions.transitionTime

    -- Default is this "magic number"...
    else
        transitionTime = 0.75
    end


    -- "Don't slow" should not be applied to the rotation speed.
    local rotationTime = transitionTime


    -- If the "Don't slow" option is selected, we have to check
    -- if actually a faster transition time is possible.
    if transitionTime > 0 and newSituation and newSituation.cameraActions.timeIsMax then
      local difference = math.abs(newZoomLevel - GetCameraZoom())
      local linearSpeed = difference / transitionTime
      local currentSpeed = tonumber(GetCVar("cameraZoomSpeed"))
      if linearSpeed < currentSpeed then
          -- min time 10 frames
          transitionTime = math.max(10*secondsPerFrame, difference / currentSpeed)
      end
    end

    -- print("transitionTime", transitionTime)


    -- Start the actual easing.

    local easeFunction = LibEasing[self.db.profile.easingZoom]
    if settingView or restoringView then
        easeFunction = LibEasing.Linear
    else
        -- We only need to zoom when not going into a view.
        -- Whenever the zoom changes we need to reset the reactiveZoomTarget.
        reactiveZoomTarget = nil
        LibCamera:SetZoom(newZoomLevel, transitionTime, easeFunction)
    end

    EaseShoulderOffset(newShoulderOffset, transitionTime, easeFunction)


    -- Set default values (possibly for new situation, may be nil).
    self.currentSituationID = newSituationID
    self:ApplyDefaultCameraSettings(newSituationID, true)

    -- Set situation specific values.
    -- (Except shoulder offset, which we are easing above.)
    if newSituation then

        -- Start rotating if applicable.
        self:StartRotation(newSituation, rotationTime)

        for cvar, value in pairs(newSituation.cameraCVars) do
            if cvar ~= "test_cameraOverShoulder" then
                DC_SetCVar(cvar, value)
            end
        end

        self:SendMessage("DC_SITUATION_ENTERED")
    end

end


function DynamicCam:GetSituationList()
    local situationList = {}

    for id, situation in pairs(self.db.profile.situations) do
        local prefix = ""
        local suffix = ""
        local customPrefix = ""

        if self.currentSituationID == id then
            prefix = "|cFF00FF00"
            suffix = "|r"
        elseif not situation.enabled then
            prefix = "|cFF808A87"
            suffix = "|r"
        elseif conditionExecutionCache[id] then
            prefix = "|cFF63B8FF"
            suffix = "|r"
        end

        if string.find(id, "custom") then
            customPrefix = "Custom: "
        end

        situationList[id] = prefix..customPrefix..situation.name..suffix
    end

    return situationList
end

function DynamicCam:CopySituationInto(fromID, toID)
    -- make sure that both from and to are valid situationIDs
    if not fromID or not toID or fromID == toID or not self.db.profile.situations[fromID] or not self.db.profile.situations[toID] then
        -- print("CopySituationInto has invalid from or to!")
        return
    end

    local from = self.db.profile.situations[fromID]
    local to = self.db.profile.situations[toID]

    -- copy settings over
    to.enabled = from.enabled

    -- a more robust solution would be much better!
    to.cameraActions = {}
    for key, value in pairs(from.cameraActions) do
        to.cameraActions[key] = from.cameraActions[key]
    end

    to.view = {}
    for key, value in pairs(from.view) do
        to.view[key] = from.view[key]
    end

    to.extras = {}
    for key, value in pairs(from.extras) do
        to.extras[key] = from.extras[key]
    end

    to.cameraCVars = {}
    for key, value in pairs(from.cameraCVars) do
        to.cameraCVars[key] = from.cameraCVars[key]
    end

    self:SendMessage("DC_SITUATION_UPDATED", toID)
end

function DynamicCam:UpdateSituation(situationID)
    local situation = self.db.profile.situations[situationID]
    if situation and situationID == self.currentSituationID then
        -- apply cvars
        for cvar, value in pairs(situation.cameraCVars) do
            DC_SetCVar(cvar, value)
        end
        self:ApplyDefaultCameraSettings()
    end
    DC_RunScript(situation.executeOnInit, situationID)
    self:RegisterSituationEvents(situationID)
    self:EvaluateSituations()
end

function DynamicCam:CreateCustomSituation(name)
    -- search for a clear id
    local highest = 0

    -- go through each and every situation, look for the custom ones, and find the
    -- highest custom id
    for id, situation in pairs(self.db.profile.situations) do
        local i, j = string.find(id, "custom")

        if i and j then
            local num = tonumber(string.sub(id, j+1))

            if num and num > highest then
                highest = num
            end
        end
    end

    -- copy the default situation into a new table
    local newSituationID = "custom"..(highest+1)
    local newSituation = copyTable(self.defaults.profile.situations["**"])

    newSituation.name = name

    -- create the entry in the profile with an id 1 higher than the highest already customID
    self.db.profile.situations[newSituationID] = newSituation

    -- make sure that the options panel reselects a situation
    if Options then
        Options:SelectSituation(newSituationID)
    end

    self:SendMessage("DC_SITUATION_UPDATED", newSituationID)
    return newSituation, newSituationID
end

function DynamicCam:DeleteCustomSituation(situationID)
    if not self.db.profile.situations[situationID] then
        -- print("Cannot delete this situation since it doesn't exist", situationID)
    end

    if not string.find(situationID, "custom") then
        -- print("Cannot delete a non-custom situation")
    end

    -- if we're currently in this situation, exit it
    if self.currentSituationID == situationID then
        self:ChangeSituation(situationID, nil)
    end

    -- delete the situation
    self.db.profile.situations[situationID] = nil

    -- make sure that the options panel reselects a situation
    if Options then
        Options:ClearSelection()
        Options:SelectSituation()
    end

    -- EvaluateSituations because we might have changed the current situation
    self:EvaluateSituations()
end


-------------
-- UTILITY --
-------------
function DynamicCam:ApplyDefaultCameraSettings(newSituationID, noShoulderOffsetChange)

    -- print("ApplyDefaultCameraSettings", newSituationID, GetTime())

    local curSituation = self.db.profile.situations[self.currentSituationID]

    if newSituationID then
        curSituation = self.db.profile.situations[newSituationID]
    end

    -- apply default settings if the current situation isn't overriding them
    for cvar, value in pairs(self.db.profile.standardCvars) do
        if not curSituation or not curSituation.cameraCVars[cvar] then

            -- ApplyDefaultCameraSettings() is called in the beginning of ExitSituation().
            -- But when exiting a situation, we want to ease-restore the shoulderOffset
            -- instead of setting it instantaneously here.
            if cvar ~= "test_cameraOverShoulder" or not noShoulderOffsetChange then
                DC_SetCVar(cvar, value)
            end
        end
    end

    -- print("Finished ApplyDefaultCameraSettings", newSituationID, GetTime())
end


-- Used by ChangeSituation() to determine if a stored zoom should
-- be restored when returning to a situation.
function DynamicCam:ShouldRestoreZoom(oldSituationID, newSituationID)

    -- print("Should Restore Zoom")

    if self.db.profile.zoomRestoreSetting == "never" then
        -- print("Setting is never.")
        return false
    end


    -- Restore if we're just exiting a situation, and have a stored value for default.
    -- (This is the case for both "always" and "adaptive".)
    if not newSituationID then
        if lastZoom["default"] then
            -- print("Restoring saved zoom for default.", lastZoom["default"])
            return true, lastZoom["default"]
        else
            -- print("Not restoring zoom because returning to default with no saved value.")
            return false
        end
    end


    -- Don't restore if we don't have a saved zoom value.
    -- (Also the case for both "always" and "adaptive".)
    if not lastZoom[newSituationID] then
        -- print("Not restoring zoom because we have no saved value for this situation.")
        return false
    end

    -- From now on we know that we are entering a new situation and have a stored zoom.

    local newSituation = self.db.profile.situations[newSituationID]
    -- Don't restore zoom if we're about to go into a view.
    if newSituation.view.enabled then
        -- print("Not restoring zoom because entering a view.")
        return false
    end


    local restoreZoom = lastZoom[newSituationID]
    if self.db.profile.zoomRestoreSetting == "always" then
        -- print("Setting is always.")
        return true, restoreZoom
    end


    -- The following are for the zoomRestoreSetting == "adaptive" setting.
    -- print("Setting is adaptive.")

    -- Only restore zoom if returning to the same situation
    if oldSituationID and lastSituation[oldSituationID] ~= newSituationID then
        -- print("Not restoring zoom because this is not the situation we came from.")
        return false
    end


    local a = newSituation.cameraActions
    -- Restore zoom based on newSituation zoomSetting.
    if a.zoomSetting == "off" then
        -- print("Not restoring zoom because new situation has no zoom setting.")
        return false
    end

    if a.zoomSetting == "set" then
        -- print("Not restoring zoom because new situation has a fixed zoom setting.")
        return false
    end

    if a.zoomSetting == "range" then
        -- only restore zoom if zoom will be in the range
        if a.zoomMin <= restoreZoom + .5 and
           a.zoomMax >= restoreZoom - .5 then
            return true, restoreZoom
        else
            return false
        end
    end

    if a.zoomSetting == "in" then
        -- Only restore if the stored zoom level is smaller or equal to the situation value
        -- and do not zoom out.
        if a.zoomValue >= restoreZoom - .5 and GetCameraZoom() > restoreZoom then
            return true, restoreZoom
        else
            -- print("Not restoring because saved value", restoreZoom, "is not smaller than zoom IN of situation.")
            return false
        end
    elseif a.zoomSetting == "out" then
        -- restore zoom if newSituation is zooming out and we would already be zooming out farther
        if a.zoomValue <= restoreZoom + .5 and GetCameraZoom() < restoreZoom then
            return true, restoreZoom
        else
            -- print("Not restoring because saved value", restoreZoom, "is not greater than zoom OUT of situation.")
            return false
        end
    end

    -- if nothing else, don't restore
    return false
end






-----------------------
-- NON-REACTIVE ZOOM --
-----------------------
-- Notice: The feature of zooming to the smallest third person zoom level does only work good for ReactiveZoom.
-- In NonReactiveZoom it only works if you set the zoom speed to max.
-- That's why we are not doing it for NonReactiveZoom.
local function NonReactiveZoom(zoomIn, increments)
    -- print("NonReactiveZoom", zoomIn, increments, GetCameraZoom())

    -- Stop zooming that might currently be in progress from a situation change.
    LibCamera:StopZooming(true)

    -- If we are not using this from within ReactiveZoom, we can also use the increment multiplier here.
    if not DynamicCam.db.profile.reactiveZoom.enabled then
        increments = increments + DynamicCam.db.profile.reactiveZoom.addIncrementsAlways

    else
        -- This is needed to correct reactiveZoomTarget in case the target is missed.
        -- print("NonReactiveZoom starting", GetCameraZoom(), GetTime())
        nonReactiveZoomStarted = true
        nonReactiveZoomInProgress = false
        nonReactiveZoomStartValue = GetCameraZoom()
    end

    if zoomIn then
        OldCameraZoomIn(increments)
    else
        OldCameraZoomOut(increments)
    end
end


local function NonReactiveZoomIn(increments)
    -- No idea, why WoW does in-out-in-out with increments 0 after each mouse wheel turn.
    if increments == 0 then return end
    NonReactiveZoom(true, increments)
end

local function NonReactiveZoomOut(increments)
    -- No idea, why WoW does in-out-in-out with increments 0 after each mouse wheel turn.
    if increments == 0 then return end

    if storeMinZoom then
        -- print("User zoomed out beyond min value. Interrupting store process.")
        storeMinZoom = false
    end

    NonReactiveZoom(false, increments)
end


-------------------
-- REACTIVE ZOOM --
-------------------

local function clearZoomTarget(wasInterrupted)
    if not wasInterrupted then
        reactiveZoomTarget = nil
    end
end

local function ReactiveZoom(zoomIn, increments)
    -- print("ReactiveZoom", zoomIn, increments, reactiveZoomTarget)

    increments = increments or 1

    -- If this is a "mouse wheel" CameraZoomIn/CameraZoomOut, increments is 1.
    -- Unlike a CameraZoomIn/CameraZoomOut from within LibCamera.SetZoomUsingCVar().
    if increments == 1 then
        local currentZoom = GetCameraZoom()

        local addIncrementsAlways = DynamicCam.db.profile.reactiveZoom.addIncrementsAlways
        local addIncrements = DynamicCam.db.profile.reactiveZoom.addIncrements
        local maxZoomTime = DynamicCam.db.profile.reactiveZoom.maxZoomTime
        local incAddDifference = DynamicCam.db.profile.reactiveZoom.incAddDifference
        local easingFunc = DynamicCam.db.profile.reactiveZoom.easingFunc


        -- scale increments up
        increments = increments + addIncrementsAlways

        if reactiveZoomTarget and math.abs(reactiveZoomTarget - currentZoom) > incAddDifference then
            increments = increments + addIncrements
        end



        -- if we've changed directions, make sure to reset
        if zoomIn then
            if reactiveZoomTarget and reactiveZoomTarget > currentZoom then
                reactiveZoomTarget = nil
            end
        else
            if reactiveZoomTarget and reactiveZoomTarget < currentZoom then
                reactiveZoomTarget = nil
            end
        end

        -- if there is already a target zoom, base off that one, or just use the current zoom
        reactiveZoomTarget = reactiveZoomTarget or currentZoom


        -- Always stop at closest third person zoom level.
        local minZoom = GetMinZoom() or 1.5

        if zoomIn then

            if reactiveZoomTarget - increments < minZoom then

                if reactiveZoomTarget > minZoom then
                    -- print("go to minZoom", minZoom)
                    reactiveZoomTarget = minZoom

                    -- Also update the increments if we need to make a NonReactiveZoom below,
                    -- in case of "zoomTime < secondsPerFrame".
                    increments = currentZoom - minZoom
                else
                    -- print("go to 0")
                    reactiveZoomTarget = 0

                    -- No need to update increments because any zoom target below minZoom
                    -- will result in 0 automatically.
                end

            else
                reactiveZoomTarget = math.max(0, reactiveZoomTarget - increments)
            end


        -- zoom out
        else

            -- From first person go directly into closest third person.
            if currentZoom == 0 then
                -- print("Giving this to non-reactive zoom")
                NonReactiveZoomOut(0.05)

                -- When this zoom is finished, store the minimal zoom distance,
                -- such that we can also use it while zooming in.
                if not IsMounted() then
                    storeMinZoom = true
                end

                return
            else
                reactiveZoomTarget = math.min(GetCVar("cameraDistanceMaxZoomFactor")*15, reactiveZoomTarget + increments)
            end
        end


        -- if we don't need to zoom because we're at the max limits, then don't
        if (reactiveZoomTarget == 39 and currentZoom == 39) or (reactiveZoomTarget == 0 and currentZoom == 0) then
            return
        end


        -- get the current time to zoom if we were going linearly or use maxZoomTime, if that's too high
        local zoomTime = math.min(maxZoomTime, math.abs(reactiveZoomTarget - currentZoom) / tonumber(GetCVar("cameraZoomSpeed")) )


        -- print ("Want to get from", currentZoom, "to", reactiveZoomTarget, "in", zoomTime, "with one frame being", secondsPerFrame)
        if zoomTime < secondsPerFrame then
            -- print("No easing for you", zoomTime, secondsPerFrame, increments)

            if zoomIn then
                NonReactiveZoomIn(increments)
            else
                NonReactiveZoomOut(increments)
            end
        else
            -- print("REACTIVE ZOOM start", GetTime())
            -- LibCamera:SetZoom(reactiveZoomTarget, zoomTime, LibEasing[easingFunc], function() print("REACTIVE ZOOM end", GetTime()) end)
            LibCamera:SetZoom(reactiveZoomTarget, zoomTime, LibEasing[easingFunc])
        end

    else
        -- Called from within LibCamera.SetZoomUsingCVar(), through SetZoom() when the target zoom was missed.
        -- print("...this is no mouse wheel call!", increments)

        if zoomIn then
            NonReactiveZoomIn(increments)
        else
            NonReactiveZoomOut(increments)
        end
    end
end


local function ReactiveZoomIn(increments)
    -- No idea, why WoW does in-out-in-out with increments 0 after each mouse wheel turn.
    if increments == 0 then return end
    ReactiveZoom(true, increments)
end

local function ReactiveZoomOut(increments)
    -- No idea, why WoW does in-out-in-out with increments 0 after each mouse wheel turn.
    if increments == 0 then return end

    if storeMinZoom then
        -- print("User zoomed out beyond min value. Interrupting store process.")
        storeMinZoom = false
    end

    ReactiveZoom(false, increments)
end


function DynamicCam:ReactiveZoomOn()
    CameraZoomIn = ReactiveZoomIn
    CameraZoomOut = ReactiveZoomOut

    reactiveZoomTarget = GetCameraZoom()
end

function DynamicCam:ReactiveZoomOff()
    CameraZoomIn = NonReactiveZoomIn
    CameraZoomOut = NonReactiveZoomOut

    reactiveZoomTarget = nil
end



------------
-- EVENTS --
------------
function DynamicCam:EventHandler(event)

    -- When entering combat, we have to act now.
    -- Otherwise, we might not be able to call protected functions like UIParent:Show().
    if event == "PLAYER_REGEN_DISABLED" then
        DynamicCam:EvaluateSituations()
    else
        evaluateSituationsNextFrame = true
    end

    -- double the event, since a lot of events happen before the condition turns out to be true
    -- Ludius (17.10.2020): Probably not needed any more now that we are
    -- calling EvaluateSituations() in the next frame..
    -- self:ScheduleTimer(function() evaluateSituationsNextFrame = true end, 0.2)
end

function DynamicCam:RegisterEvents()
    self:RegisterEvent("PLAYER_CONTROL_GAINED", "EventHandler")

    for situationID, situation in pairs(self.db.profile.situations) do
        self:RegisterSituationEvents(situationID)
    end
end

function DynamicCam:RegisterSituationEvents(situationID)
    local situation = self.db.profile.situations[situationID]
    if situation and situation.events then
        for i, event in pairs(situation.events) do
            if not events[event] then
                events[event] = true
                self:RegisterEvent(event, "EventHandler")
                -- print("Registered for event:", event)
            end
        end
    end
end

function DynamicCam:DC_SITUATION_ENABLED(message, situationID)
    self:EvaluateSituations()
end

function DynamicCam:DC_SITUATION_DISABLED(message, situationID)
    self:EvaluateSituations()
end

function DynamicCam:DC_SITUATION_UPDATED(message, situationID)
    self:UpdateSituation(situationID)
end

function DynamicCam:DC_BASE_CAMERA_UPDATED(message)
    self:ApplyDefaultCameraSettings()
end


--------------
-- DATABASE --
--------------
local firstDynamicCamLaunch = false
StaticPopupDialogs["DYNAMICCAM_FIRST_RUN"] = {
    text = "Welcome to your first launch of DynamicCam!\n\nIt is highly suggested to load a preset to start, since the addon starts completely unconfigured. Go to the \"Profiles\"->\"Profile presets\" tab to find some presets.",
    button1 = "OK",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    OnAccept = function()
        InterfaceOptionsFrame_OpenToCategory(Options.menu)
        InterfaceOptionsFrame_OpenToCategory(Options.menu)
    end,
    OnCancel = function(_, reason)
    end,
}

StaticPopupDialogs["DYNAMICCAM_FIRST_LOAD_PROFILE"] = {
    text = "The current DynamicCam profile is fresh and probably empty. Go to the \"Profiles\"->\"Profile presets\" tab to find some presets.",
    button1 = "OK",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    OnAccept = function()
        InterfaceOptionsFrame_OpenToCategory(Options.menu)
        InterfaceOptionsFrame_OpenToCategory(Options.menu)
    end,
    OnCancel = function(_, reason)
    end,
}

function DynamicCam:InitDatabase()
    self.db = LibStub("AceDB-3.0"):New("DynamicCamDB", self.defaults, true)
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
    self.db.RegisterCallback(self, "OnDatabaseShutdown", "Shutdown")

    if not DynamicCamDB.profiles then
        firstDynamicCamLaunch = true
    else
        -- reset db if we've got a really old version
        local veryOldVersion = false
        for profileName, profile in pairs(DynamicCamDB.profiles) do
            if profile.standardCvars and profile.standardCvars["cameraovershoulder"] then
                veryOldVersion = true
            end
        end

        if veryOldVersion then
            self:Print("Detected very old version, resetting DB, sorry about that!")
            self.db:ResetDB()
        end

        -- modernize each profile
        for profileName, profile in pairs(DynamicCamDB.profiles) do
            self:ModernizeProfile(profile)
        end

    end
end

function DynamicCam:ModernizeProfile(profile)
    if not profile.version then
        profile.version = 1
    end

    local startVersion = profile.version

    if profile.version == 1 then
        if profile.standardCvars and profile.standardCvars["test_cameraLockedTargetFocusing"] ~= nil then
            profile.standardCvars["test_cameraLockedTargetFocusing"] = nil
        end

        upgradingFromOldVersion = true
        profile.version = 2
        profile.firstRun = false
    end

    -- modernize each situation
    if profile.situations then
        for situationID, situation in pairs(profile.situations) do
            self:ModernizeSituation(situation, startVersion)
        end
    end
end

function DynamicCam:ModernizeSituation(situation, version)
    if version == 1 then
        -- clear unused nameplates db stuff
        if situation.extras then
            situation.extras["nameplates"] = nil
            situation.extras["friendlyNameplates"] = nil
            situation.extras["enemyNameplates"] = nil
        end

        -- update targetlock features
        if situation.targetLock then
            if situation.targetLock.enabled then
                if not situation.cameraCVars then
                    situation.cameraCVars = {}
                end

                if situation.targetLock.onlyAttackable ~= nil and situation.targetLock.onlyAttackable == false then
                    situation.cameraCVars["test_cameraTargetFocusEnemyEnable"] = 1
                    situation.cameraCVars["test_cameraTargetFocusInteractEnable"] = 1
                else
                    situation.cameraCVars["test_cameraTargetFocusEnemyEnable"] = 1
                end
            end

            situation.targetLock = nil
        end

        -- update camera rotation
        if situation.cameraActions then
            -- convert to yaw degrees instead of rotate degrees
            if situation.cameraActions.rotateDegrees then
                situation.cameraActions.yawDegrees = situation.cameraActions.rotateDegrees
                situation.cameraActions.pitchDegrees = 0
                situation.cameraActions.rotateDegrees = nil
            end

            -- convert old scalar rotate speed to something that's in degrees/second
            if situation.cameraActions.rotateSpeed and situation.cameraActions.rotateSpeed < 5 then
                situation.cameraActions.rotateSpeed = situation.cameraActions.rotateSpeed * tonumber(GetCVar("cameraYawMoveSpeed"))
            end
        end
    end
end

function DynamicCam:RefreshConfig()

    -- shutdown the addon
    if started then
        self:Shutdown()
    end

    -- situation is active, but db killed it
    if self.currentSituationID then
        self.currentSituationID = nil
    end

    -- clear the options panel so that it reselects
    -- make sure that options panel selects a situation
    if Options then
        Options:ClearSelection()
        Options:SelectSituation()
    end

    -- present a menu that loads a set of defaults, if this is the profiles first run
    if self.db.profile.firstRun then
        if firstDynamicCamLaunch then
            StaticPopup_Show("DYNAMICCAM_FIRST_RUN")
            firstDynamicCamLaunch = false
        else
            StaticPopup_Show("DYNAMICCAM_FIRST_LOAD_PROFILE")
        end
        self.db.profile.firstRun = false
    end

    -- start the addon back up
    if not started then
        self:Startup()
    end

    -- run all situations's advanced init script
    for id, situation in pairs(self.db.profile.situations) do
        DC_RunScript(situation.executeOnInit, id)
    end
end


-------------------
-- CHAT COMMANDS --
-------------------
local function tokenize(str, delimitor)
    local tokens = {}
    for token in str:gmatch(delimitor or "%S+") do
        table.insert(tokens, token)
    end
    return tokens
end

StaticPopupDialogs["DYNAMICCAM_NEW_CUSTOM_SITUATION"] = {
    text = "Enter name for custom situation:",
    button1 = "Create!",
    button2 = "Cancel",
    timeout = 0,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    OnShow = function (self, data)
        self.editBox:SetFocus()
    end,
    OnAccept = function (self, data)
        DynamicCam:CreateCustomSituation(self.editBox:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        DynamicCam:CreateCustomSituation(self:GetParent().editBox:GetText())
        self:GetParent():Hide()
    end,
}

local exportString
StaticPopupDialogs["DYNAMICCAM_EXPORT"] = {
    text = "DynamicCam Export:",
    button1 = "Done!",
    timeout = 0,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    OnShow = function (self, data)
        self.editBox:SetText(exportString)
        self.editBox:HighlightText()
    end,
    EditBoxOnEnterPressed = function(self)
        self:GetParent():Hide()
    end,
}

function DynamicCam:OpenMenu()

    if not Options then
        Options = self.Options
    end

    Options:SelectSituation()

    -- just open to the frame, double call because blizz bug
    InterfaceOptionsFrame_OpenToCategory(Options.menu)
    InterfaceOptionsFrame_OpenToCategory(Options.menu)
end

function DynamicCam:SaveViewCC(input)
    local tokens = tokenize(input)

    local viewNum = tonumber(tokens[1])

    if viewNum and viewNum <= 5 and viewNum > 1 then
        SaveView(viewNum)
    else
        self:Print("Improper view number provided.")
    end
end

function DynamicCam:ZoomInfoCC(input)
    self:Print(string.format("Zoom level: %0.2f", GetCameraZoom()))
end

function DynamicCam:ZoomSlash(input)
    local tokens = tokenize(input)

    local zoom = tonumber(tokens[1])
    local time = tonumber(tokens[2])
    local easingFuncName
    local easingFunc

    if not time then
        -- time not provided, maybe 2nd param is easingfunc?
        easingFuncName = tokens[2]
    else
        easingFuncName = tokens[3]
    end

    -- look up easing func
    if easingFuncName then
        easingFunc = LibEasing[easingFuncName] or LibEasing.InOutQuad
    end

    if zoom and (zoom <= 39 or zoom >= 0) then
        local defaultTime = math.abs(zoom - GetCameraZoom()) / tonumber(GetCVar("cameraZoomSpeed"))

        -- Whenever the zoom changes we need to reset the reactiveZoomTarget.
        reactiveZoomTarget = nil
        LibCamera:SetZoom(zoom, time or math.min(defaultTime, 0.75), easingFunc)
    end
end

function DynamicCam:PitchSlash(input)
    local tokens = tokenize(input)

    local pitch = tonumber(tokens[1])
    local time = tonumber(tokens[2])
    local easingFuncName
    local easingFunc

    if not time then
        -- time not provided, maybe 2nd param is easingfunc?
        easingFuncName = tokens[2]
    else
        easingFuncName = tokens[3]
    end

    -- look up easing func
    if easingFuncName then
        easingFunc = LibEasing[easingFuncName] or LibEasing.InOutQuad
    end

    if pitch and (pitch <= 90 or pitch >= -90) then
        LibCamera:Pitch(pitch, time or 0.75, easingFunc)
    end
end

function DynamicCam:YawSlash(input)
    local tokens = tokenize(input)

    local yaw = tonumber(tokens[1])
    local time = tonumber(tokens[2])
    local easingFuncName
    local easingFunc

    if not time then
        -- time not provided, maybe 2nd param is easingfunc?
        easingFuncName = tokens[2]
    else
        easingFuncName = tokens[3]
    end

    -- look up easing func
    if easingFuncName then
        easingFunc = LibEasing[easingFuncName] or LibEasing.InOutQuad
    end

    if yaw then
        LibCamera:Yaw(yaw, time or 0.75, easingFunc)
    end
end

function DynamicCam:PopupCreateCustomProfile()
    StaticPopup_Show("DYNAMICCAM_NEW_CUSTOM_SITUATION")
end

function DynamicCam:PopupExport(str)
    exportString = str
    StaticPopup_Show("DYNAMICCAM_EXPORT")
end

function DynamicCam:PopupExportProfile()
    self:PopupExport(self:ExportProfile())
end


-----------
-- CVARS --
-----------
function DynamicCam:ResetCVars()
    for cvar, value in pairs(self.db.profile.standardCvars) do
        DC_SetCVar(cvar, GetCVarDefault(cvar))
    end

    ResetView(1)
    ResetView(2)
    ResetView(3)
    ResetView(4)
    ResetView(5)
end









-- This is needed to correct reactiveZoomTarget in case the target is missed.
local lastZoom = GetCameraZoom()
local reactiveZoomTargetCorrectionFrame = CreateFrame("Frame")
reactiveZoomTargetCorrectionFrame:SetScript("onUpdate", function()

    if not DynamicCam.db.profile.reactiveZoom.enabled then return end

    local currentZoom = GetCameraZoom()

    if nonReactiveZoomStarted and nonReactiveZoomStartValue ~= currentZoom then
        -- print("NonReactiveZoom just Started", nonReactiveZoomStartValue, GetTime())
        nonReactiveZoomInProgress = true
        nonReactiveZoomStarted = false
    elseif nonReactiveZoomInProgress and lastZoom == currentZoom then
        -- print("NonReactiveZoom finished", GetTime())
        nonReactiveZoomInProgress = false
    end

    if not LibCamera:IsZooming() and not nonReactiveZoomStarted and not nonReactiveZoomInProgress and reactiveZoomTarget ~= currentZoom then
      -- print("Correcting reactiveZoomTarget", reactiveZoomTarget, "to", currentZoom, GetTime())
      reactiveZoomTarget = currentZoom

      if storeMinZoom then
          -- print("Storing", currentZoom, "for", GetModelId())
          minZoomValues[GetModelId()] = currentZoom
          storeMinZoom = false
      end
    end

    lastZoom = currentZoom
end)








------------------------------------
-- ReactiveZoom Visual Aid (RZVA) --
------------------------------------

local function DrawLine(f, startRelativeAnchor, startOffsetX, startOffsetY,
                           endRelativeAnchor, endOffsetX, endOffsetY,
                           thickness, r, g, b, a)

  local line = f:CreateLine()
  line:SetThickness(thickness)
  line:SetColorTexture(r, g, b, a)
  line:SetStartPoint(startRelativeAnchor, f, startOffsetX, startOffsetY)
  line:SetEndPoint(endRelativeAnchor, f, endOffsetX, endOffsetY)

end


local function SetFrameBorder(f, thickness, r, g, b, a)
  -- Bottom line.
  DrawLine(f, "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", 0, 0, thickness, r, g, b, a)
  -- Top line.
  DrawLine(f, "TOPLEFT", 0, 0, "TOPRIGHT", 0, 0, thickness, r, g, b, a)
  -- Left line.
  DrawLine(f, "BOTTOMLEFT", 0, 0, "TOPLEFT", 0, 0, thickness, r, g, b, a)
  -- Right line.
  DrawLine(f, "BOTTOMRIGHT", 0, 0, "TOPRIGHT", 0, 0, thickness, r, g, b, a)
end


local rzvaWidth = 120
local rzvaHeight = 200
local rzvaHalfWidth = rzvaWidth/2

local rzvaFrame = nil

function DynamicCam:ToggleRZVA()

    if not rzvaFrame then

        rzvaFrame = CreateFrame("Frame", "reactiveZoomVisualAid", UIParent)
        rzvaFrame:SetFrameStrata("TOOLTIP")
        rzvaFrame:SetMovable(true)
        rzvaFrame:EnableMouse(true)
        rzvaFrame:RegisterForDrag("LeftButton")
        rzvaFrame:SetScript("OnDragStart", rzvaFrame.StartMoving)
        rzvaFrame:SetScript("OnDragStop", rzvaFrame.StopMovingOrSizing)
        rzvaFrame:SetClampedToScreen(true)

        rzvaFrame:SetWidth(rzvaWidth)
        rzvaFrame:SetHeight(rzvaHeight)
        rzvaFrame:ClearAllPoints()
        rzvaFrame:SetPoint("BOTTOMLEFT", InterfaceOptionsFramePanelContainer, "BOTTOMLEFT", 45, 35)

        rzvaFrame.t = rzvaFrame:CreateTexture()
        rzvaFrame.t:SetAllPoints()
        rzvaFrame.t:SetTexture("Interface/BUTTONS/WHITE8X8")
        rzvaFrame.t:SetColorTexture(1, 1, 1, .1)

        SetFrameBorder(rzvaFrame, 2, 1, 1, 1, 1)


        rzvaFrame.cameraZoomLabel = rzvaFrame:CreateFontString()
        rzvaFrame.cameraZoomLabel:SetWidth(rzvaHalfWidth)
        rzvaFrame.cameraZoomLabel:SetJustifyH("CENTER")
        rzvaFrame.cameraZoomLabel:SetJustifyV("CENTER")
        rzvaFrame.cameraZoomLabel:SetPoint("BOTTOMRIGHT", rzvaFrame, "TOPRIGHT", 0, 19)
        rzvaFrame.cameraZoomLabel:SetFont("Fonts/FRIZQT__.TTF", 12)
        rzvaFrame.cameraZoomLabel:SetTextColor(1, .3, .3, 1)
        rzvaFrame.cameraZoomLabel:SetText("Actual\nZoom\nValue")

        rzvaFrame.cameraZoomValue = rzvaFrame:CreateFontString()
        rzvaFrame.cameraZoomValue:SetWidth(rzvaHalfWidth)
        rzvaFrame.cameraZoomValue:SetJustifyH("CENTER")
        rzvaFrame.cameraZoomValue:SetJustifyV("CENTER")
        rzvaFrame.cameraZoomValue:SetPoint("BOTTOMRIGHT", rzvaFrame, "TOPRIGHT", 0, 4)
        rzvaFrame.cameraZoomValue:SetFont("Fonts/FRIZQT__.TTF", 14)
        rzvaFrame.cameraZoomValue:SetTextColor(1, .3, .3, 1)
        rzvaFrame.cameraZoomValue:SetText(GetCameraZoom())


        rzvaFrame.reactiveZoomTargetLabel = rzvaFrame:CreateFontString()
        rzvaFrame.reactiveZoomTargetLabel:SetWidth(rzvaHalfWidth)
        rzvaFrame.reactiveZoomTargetLabel:SetJustifyH("CENTER")
        rzvaFrame.reactiveZoomTargetLabel:SetJustifyV("CENTER")
        rzvaFrame.reactiveZoomTargetLabel:SetPoint("BOTTOMLEFT", rzvaFrame, "TOPLEFT", 0, 19)
        rzvaFrame.reactiveZoomTargetLabel:SetFont("Fonts/FRIZQT__.TTF", 12)
        rzvaFrame.reactiveZoomTargetLabel:SetTextColor(.3, .3, 1, 1)
        rzvaFrame.reactiveZoomTargetLabel:SetText("Reactive\nZoom\nTarget")

        rzvaFrame.reactiveZoomTargetValue = rzvaFrame:CreateFontString()
        rzvaFrame.reactiveZoomTargetValue:SetWidth(rzvaHalfWidth)
        rzvaFrame.reactiveZoomTargetValue:SetJustifyH("CENTER")
        rzvaFrame.reactiveZoomTargetValue:SetJustifyV("CENTER")
        rzvaFrame.reactiveZoomTargetValue:SetPoint("BOTTOMLEFT", rzvaFrame, "TOPLEFT", 0, 4)
        rzvaFrame.reactiveZoomTargetValue:SetFont("Fonts/FRIZQT__.TTF", 14)
        rzvaFrame.reactiveZoomTargetValue:SetTextColor(.3, .3, 1, 1)



        rzvaFrame.zm = CreateFrame("Frame", "cameraZoomMarker", rzvaFrame)
        rzvaFrame.zm:SetWidth(rzvaHalfWidth)
        rzvaFrame.zm:SetHeight(1)
        rzvaFrame.zm:Show()
        DrawLine(rzvaFrame.zm, "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", 0, 0, 5, 1, .3, .3, 1)


        rzvaFrame.rzt = CreateFrame("Frame", "reactiveZoomTargetMarker", rzvaFrame)
        rzvaFrame.rzt:SetWidth(rzvaHalfWidth)
        rzvaFrame.rzt:SetHeight(1)
        rzvaFrame.rzt:Show()
        DrawLine(rzvaFrame.rzt, "BOTTOMRIGHT", 0, 0, "BOTTOMLEFT", 0, 0, 5, .3, .3, 1, 1)


        rzvaFrame.rzi = CreateFrame("Frame", "reactiveZoomIncrementMarker", rzvaFrame)
        rzvaFrame.rzi:SetWidth(rzvaHalfWidth)
        -- Must set points here, otherwise the texture is not created...
        rzvaFrame.rzi:SetPoint("TOP", rzvaFrame.rzt, "BOTTOM", 0, 0)
        rzvaFrame.rzi.t = rzvaFrame.rzi:CreateTexture()
        rzvaFrame.rzi.t:SetAllPoints()
        rzvaFrame.rzi.t:SetTexture("Interface/BUTTONS/WHITE8X8")
        rzvaFrame.rzi.t:SetColorTexture(1, 1, 0, 1)

        rzvaFrame:Hide()
    end

    if not rzvaFrame:IsShown() then
        rzvaFrame:Show()
    else
        rzvaFrame:Hide()
    end

end


local lastReactiveZoomTarget = reactiveZoomTarget
local reactiveZoomGraphUpdateFrame = CreateFrame("Frame")
reactiveZoomGraphUpdateFrame:SetScript("onUpdate", function()

    if not rzvaFrame or not rzvaFrame:IsShown() then return end

    rzvaFrame.zm:ClearAllPoints()
    rzvaFrame.zm:SetPoint("BOTTOMRIGHT", 0, rzvaFrame:GetHeight() - (rzvaFrame:GetHeight() * GetCameraZoom() / 39) )
    rzvaFrame.cameraZoomValue:SetText(round(GetCameraZoom(), 3))


    if DynamicCam.db.profile.reactiveZoom.enabled then

        if not rzvaFrame.rzt:IsShown() then
            rzvaFrame.rzt:Show()
            rzvaFrame.rzi:Show()
            rzvaFrame.reactiveZoomTargetLabel:SetTextColor(.3, .3, 1, 1)
            rzvaFrame.reactiveZoomTargetValue:SetTextColor(.3, .3, 1, 1)
        end

        rzvaFrame.rzt:ClearAllPoints()
        if reactiveZoomTarget then
            rzvaFrame.rzt:SetPoint("BOTTOMLEFT", 0, rzvaFrame:GetHeight() - (rzvaFrame:GetHeight()* reactiveZoomTarget / 39) )

            rzvaFrame.reactiveZoomTargetValue:SetText(round(reactiveZoomTarget, 3))

            if lastReactiveZoomTarget then
                local step = lastReactiveZoomTarget - reactiveZoomTarget

                if step > 0 then
                    rzvaFrame.rzi:SetHeight(rzvaFrame:GetHeight() * step / 39)
                    rzvaFrame.rzi:Show()
                elseif step < 0 then
                    rzvaFrame.rzi:SetHeight(rzvaFrame:GetHeight() * step / 39)
                    rzvaFrame.rzi:Show()
                else
                    rzvaFrame.rzi:Hide()
                end


            end

            lastReactiveZoomTarget = reactiveZoomTarget

        else
            rzvaFrame.rzi:Hide()
            rzvaFrame.rzt:Hide()
            rzvaFrame.reactiveZoomTargetValue:SetText("---")
        end

    else

        if rzvaFrame.rzi:IsShown() then  end
        if rzvaFrame.rzt:IsShown() then
            rzvaFrame.rzt:Hide()
            rzvaFrame.rzi:Hide()
            rzvaFrame.reactiveZoomTargetLabel:SetTextColor(.3, .3, .3, 1)
            rzvaFrame.reactiveZoomTargetValue:SetTextColor(.3, .3, .3, 1)
            rzvaFrame.reactiveZoomTargetValue:SetText("---")
        end
    end

end)











-- For debugging.
function DynamicCam:PrintTable(t, indent)
  assert(type(t) == "table", "PrintTable() called for non-table!")

  local indentString = ""
  for i = 1, indent do
    indentString = indentString .. "  "
  end

  for k, v in pairs(t) do
    if type(v) ~= "table" then
      print(indentString, k, "=", v)
    else
      print(indentString, k, "=")
      print(indentString, "  {")
      self:PrintTable(v, indent + 2)
      print(indentString, "  }")
    end
  end
end
