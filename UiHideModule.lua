local _, Addon = ...


-- For debugging:
-- local debugFrameName = "BT4Bar1"


-- Flag to remember if the UI is currently faded out.
Addon.uiHiddenTime = 0


-- Call Addon.HideUI(fadeOutTime, config) to hide UI keeping configured frames.
-- Call Addon.ShowUI(fadeInTime, true) when entering combat while UI is hidden.
--   This will show the actually hidden frames, that cannot be shown during combat,
--   but the fade out state will remain. You only see tooltips of faded-out frames.
-- Call Addon.ShowUI(fadeInTime, false) to show UI.


-- Lua API
local _G = _G
local string_find = string.find

local UIFrameFadeOut     = _G.UIFrameFadeOut
local UIFrameFadeIn      = _G.UIFrameFadeIn
local InCombatLockdown   = _G.InCombatLockdown
local GetNumGroupMembers = _G.GetNumGroupMembers
local UnitInParty        = _G.UnitInParty
local UnitInRaid         = _G.UnitInRaid


-- We need a function to change a frame's alpha without automatically showing the frame
-- (as done by the original UIFrameFade() defined in UIParent.lua).

if not ludius_FADEFRAMES then ludius_FADEFRAMES = {} end

local frameFadeManager = CreateFrame("FRAME")

local function UIFrameFadeRemoveFrame(frame)
	tDeleteItem(ludius_FADEFRAMES, frame)
end

local function UIFrameFade_OnUpdate(self, elapsed)
	local index = 1
	local frame, fadeInfo
	while ludius_FADEFRAMES[index] do
		frame = ludius_FADEFRAMES[index]
		fadeInfo = ludius_FADEFRAMES[index].fadeInfo
		-- Reset the timer if there isn't one, this is just an internal counter
		if not fadeInfo.fadeTimer then
			fadeInfo.fadeTimer = 0
		end
		fadeInfo.fadeTimer = fadeInfo.fadeTimer + elapsed

		-- If the fadeTimer is less then the desired fade time then set the alpha otherwise hold the fade state, call the finished function, or just finish the fade
		if fadeInfo.fadeTimer < fadeInfo.timeToFade then
			if fadeInfo.mode == "IN" then
				frame:SetAlpha((fadeInfo.fadeTimer / fadeInfo.timeToFade) * (fadeInfo.endAlpha - fadeInfo.startAlpha) + fadeInfo.startAlpha)
			elseif fadeInfo.mode == "OUT" then
				frame:SetAlpha(((fadeInfo.timeToFade - fadeInfo.fadeTimer) / fadeInfo.timeToFade) * (fadeInfo.startAlpha - fadeInfo.endAlpha) + fadeInfo.endAlpha)
			end
		else
			frame:SetAlpha(fadeInfo.endAlpha)
      -- Complete the fade and call the finished function if there is one
      UIFrameFadeRemoveFrame(frame)
      if fadeInfo.finishedFunc then
        fadeInfo.finishedFunc(fadeInfo.finishedArg1, fadeInfo.finishedArg2, fadeInfo.finishedArg3, fadeInfo.finishedArg4)
        fadeInfo.finishedFunc = nil
      end
		end

		index = index + 1
	end

	if #ludius_FADEFRAMES == 0 then
		self:SetScript("OnUpdate", nil)
	end
end

local function UIFrameFade(frame, fadeInfo)
	if not frame then return end

  -- We make sure that we always call this with mode, startAlpha and endAlpha.
  assert(fadeInfo.mode, fadeInfo.startAlpha, fadeInfo.endAlpha)

  frame.fadeInfo = fadeInfo
	frame:SetAlpha(fadeInfo.startAlpha)

	local index = 1
	while ludius_FADEFRAMES[index] do
		-- If frame is already set to fade then return
		if ludius_FADEFRAMES[index] == frame then
			return
		end
		index = index + 1
	end
	tinsert(ludius_FADEFRAMES, frame)
	frameFadeManager:SetScript("OnUpdate", UIFrameFade_OnUpdate)
end







-- A function to set a frame's alpha depending on mouse over and
-- whether we are fading/faded out or not.
local function SetMouseOverAlpha(frame)
  -- Only do something to frames for which the hovering was activated.
  if frame.ludius_mouseOver == nil then return end

  -- Fading or faded out.
  if frame.ludius_fadeout then

    -- If the mouse is hovering over the status bar, show it with alpha 1.
    if frame.ludius_mouseOver then
      -- In case we are currently fading out,
      -- interrupt the fade out in progress.
      UIFrameFadeRemoveFrame(frame)
      frame:SetAlpha(1)

    -- Otherwise use the faded out alpha.
    else
      frame:SetAlpha(frame.ludius_alphaAfterFadeOut)
    end

  end
end

local function SetMouseOverFading(barManager)
  for _, frame in pairs(barManager.bars) do
    frame:HookScript("OnEnter", function()
      barManager.ludius_mouseOver = true
      SetMouseOverAlpha(barManager)
    end)
    frame:HookScript("OnLeave", function()
      barManager.ludius_mouseOver = false
      SetMouseOverAlpha(barManager)
    end)
  end
end


if Bartender4 then
  hooksecurefunc(Bartender4:GetModule("StatusTrackingBar"), "OnEnable", function()
    SetMouseOverFading(BT4StatusBarTrackingManager)
  end)
else
  hooksecurefunc(StatusTrackingBarManager, "AddBarFromTemplate", SetMouseOverFading)
end


if IsAddOnLoaded("GW2_UI") then
  -- GW2_UI seems to offer no way of hooking any of its functions.
  -- So we have to do it like this.
  local enterWorldFrame = CreateFrame("Frame")
  enterWorldFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  enterWorldFrame:SetScript("OnEvent", function()
    if GwExperienceFrame then
      GwExperienceFrame:HookScript("OnEnter", function()
        GwExperienceFrame.ludius_mouseOver = true
        SetMouseOverAlpha(GwExperienceFrame)
      end)
      GwExperienceFrame:HookScript("OnLeave", function()
        GwExperienceFrame.ludius_mouseOver = false
        SetMouseOverAlpha(GwExperienceFrame)
      end)
    end
  end)
end



-- To hide the tooltip of bag items.
-- (While we are actually hiding other frames to suppress their tooltips,
-- this is not practical for the bag, as openning my cause a slight lag.)
local function GameTooltipHider(self)

  if Addon.uiHiddenTime == 0 or not self then return end

  local ownerName = nil
  if self:GetOwner() then
    ownerName = self:GetOwner():GetName()
  end
  if ownerName == nil then return end

  if string_find(ownerName, "^ContainerFrame") or ownerName == "ChatFrameChannelButton" then
    self:Hide()
  -- else
    -- print(ownerName)
  end
end

GameTooltip:HookScript("OnTooltipSetDefaultAnchor", GameTooltipHider)
GameTooltip:HookScript("OnTooltipSetItem", GameTooltipHider)
GameTooltip:HookScript("OnShow", GameTooltipHider)




local function ConditionalHide(frame)
  if not frame then return end

  -- if frame:GetName() == debugFrameName then print("ConditionalHide", frame:GetName()) end

  -- Checking for combat lockdown is not this function's concern.
  -- Functions calling it must make sure, it is not  called in combat lockdown.
  if frame:IsProtected() and InCombatLockdown() then
    print("ERROR: Should not try to hide", frame:GetName(), "in combat lockdown!")
  end

  if frame.ludius_shownBeforeFadeOut == nil then
    -- if frame:GetName() == debugFrameName then print("Remember it was shown") end
    frame.ludius_shownBeforeFadeOut = frame:IsShown()
  end

  if frame:IsShown() then
    frame:Hide()
  end
end


local function ConditionalShow(frame)
  if not frame or frame.ludius_shownBeforeFadeOut == nil then return end

  -- if frame:GetName() == debugFrameName then print("ConditionalShow", frame:GetName(), frame.ludius_shownBeforeFadeOut) end

  -- Don't accidentally bring back party or raid frames when we are not in the party or raid any more.
  if string_find(frame:GetName(), "^PartyMemberFrame") and not UnitInParty("player") then return end
  if string_find(frame:GetName(), "^CompactRaidFrame") and not UnitInRaid("player") then return end

  if frame:IsProtected() and InCombatLockdown() then
    print("ERROR: Should not try to show", frame:GetName(), "in combat lockdown!")
  end

  if frame.ludius_shownBeforeFadeOut and not frame:IsShown() then
    -- if frame:GetName() == debugFrameName then print("Have to show it again!") end
    frame:Show()
  end
  frame.ludius_shownBeforeFadeOut = nil
end



-- To restore frames to their pre-hide ignore-parent-alpha state,
-- we remember it in the ludius_ignoreParentAlphaBeforeFadeOut variable.
local function ConditionalSetIgnoreParentAlpha(frame, ignoreParentAlpha)
  if not frame then return end

  if frame.ludius_ignoreParentAlphaBeforeFadeOut == nil then
    frame.ludius_ignoreParentAlphaBeforeFadeOut = frame:IsIgnoringParentAlpha()
  end

  if frame:IsIgnoringParentAlpha() ~= ignoreParentAlpha then
    frame:SetIgnoreParentAlpha(ignoreParentAlpha)
  end
end

local function ConditionalResetIgnoreParentAlpha(frame)
  if not frame or frame.ludius_ignoreParentAlphaBeforeFadeOut == nil then return end

  if frame:IsIgnoringParentAlpha() ~= frame.ludius_ignoreParentAlphaBeforeFadeOut then
    frame:SetIgnoreParentAlpha(frame.ludius_ignoreParentAlphaBeforeFadeOut)
  end
  frame.ludius_ignoreParentAlphaBeforeFadeOut = nil
end




-- The alert frames have to be dealt with as they are created.
-- https://www.wowinterface.com/forums/showthread.php?p=337803
-- For testing:
-- /run UIParent:SetAlpha(0.5)
-- /run NewMountAlertSystem:ShowAlert("123") NewMountAlertSystem:ShowAlert("123")
-- /run CovenantRenownToast:ShowRenownLevelUpToast(C_Covenants.GetActiveCovenantID(), 40)

-- Collect alert frames that are created.
local collectedAlertFrames = {}
-- A flag for alert frames that are created/collected while the UI is hidden.
local currentAlertFramesIgnoreParentAlpha = false

local function AlertFramesSetIgnoreParentAlpha(ignoreParentAlpha)
  currentAlertFramesIgnoreParentAlpha = ignoreParentAlpha
  for _, v in pairs(collectedAlertFrames) do
    ConditionalSetIgnoreParentAlpha(v, ignoreParentAlpha)
  end
end

local function AlertFramesResetIgnoreParentAlpha()
  currentAlertFramesIgnoreParentAlpha = false
  for _, v in pairs(collectedAlertFrames) do
    ConditionalResetIgnoreParentAlpha(v)
  end
end


local function CollectAlertFrame(_, frame)
  if frame and not frame.ludius_collected then
    tinsert(collectedAlertFrames, frame)
    frame.ludius_collected = true

    if currentAlertFramesIgnoreParentAlpha then
      ConditionalSetIgnoreParentAlpha(frame, currentAlertFramesIgnoreParentAlpha)
    end
  end
end

for _, subSystem in pairs(AlertFrame.alertFrameSubSystems) do
  local pool = type(subSystem) == 'table' and subSystem.alertFramePool
  if type(pool) == 'table' and type(pool.resetterFunc) == 'function' then
    hooksecurefunc(pool, "resetterFunc", CollectAlertFrame)
  end
end




-- If targetIgnoreParentAlpha == true, targetAlpha is the frame's alpha.
-- If targetIgnoreParentAlpha == false, targetAlpha is the UIParent's alpha.
local function FadeOutFrame(frame, duration, targetIgnoreParentAlpha, targetAlpha)

  if not frame then return end

  -- Prevent callback functions of currently active timers.
  UIFrameFadeRemoveFrame(frame)

  -- if frame:GetName() == debugFrameName then print("FadeOutFrame", frame:GetName(), targetIgnoreParentAlpha, targetAlpha) end

  -- To use UIFrameFade() which is the same as UIFrameFadeOut, but with a callback function.
  local fadeInfo = {}
  fadeInfo.mode = "OUT"
  fadeInfo.timeToFade = duration
  fadeInfo.finishedArg1 = frame
  fadeInfo.finishedFunc = function(finishedArg1)
    if finishedArg1:GetName() == debugFrameName then print("Fade out finished", finishedArg1:GetName(), targetAlpha) end
    if targetAlpha == 0 then
      if finishedArg1:GetName() == debugFrameName then print("...and hiding!", targetAlpha) end

      if not frame:IsProtected() or not InCombatLockdown() then
        ConditionalHide(finishedArg1)
      end
    end
  end


  -- Frame should henceforth ignore parent alpha.
  if targetIgnoreParentAlpha then

    -- ludius_alphaBeforeFadeOut is only set, if this is a fresh FadeOutFrame().
    -- It is set to nil after a FadeOutFrame is completed.
    -- Otherwise, we might falsely asume a wrong ludius_alphaBeforeFadeOut
    -- value while a fadein is still in progress.
    if frame.ludius_alphaBeforeFadeOut == nil then
      frame.ludius_alphaBeforeFadeOut = frame:GetAlpha()
    end


    -- This is to let SetMouseOverAlpha() know whether we are
    -- currently fading/faded in or fading/faded out.
    -- Notice that we cannot use ludius_alphaBeforeFadeOut or ludius_alphaAfterFadeOut as this flag,
    -- because ludius_fadeout is unset at the beginning of a fade out
    -- and ludius_alphaBeforeFadeOut is unset at the end of a fade out.
    -- For an OnEnable/OnLeave during fade out, we do not want the alpha to change.
    frame.ludius_fadeout = true
    -- This is to let SetMouseOverAlpha() know which
    -- alpha to go back to OnLeave while the frame is faded or fading out.
    frame.ludius_alphaAfterFadeOut = targetAlpha
    SetMouseOverAlpha(frame)


    -- Frame was adhering to parent alpha before.
    -- Start the fade with UIParent's current alpha.
    if not frame:IsIgnoringParentAlpha() then
      fadeInfo.startAlpha = UIParent:GetAlpha()

    -- Frame was already ignoring parent alpha before.
    else
      fadeInfo.startAlpha = frame:GetAlpha()

    end
    fadeInfo.endAlpha = targetAlpha

    ConditionalSetIgnoreParentAlpha(frame, true)


  -- Frame should henceforth adhere to parent alpha.
  else

    -- Frame was ignoring parent alpha before.
    -- Start the fade with the frame's alpha, fade to UIParent's target alpha
    -- and only then unset ignore parent alpha.
    -- Notice that the frame's alpha is not overriden by parent alpha but combined.
    -- So we have to set the child's alpha to 1 at the same time as we stop ignoring
    -- parent alpha.
    if frame:IsIgnoringParentAlpha() then
      fadeInfo.startAlpha = frame:GetAlpha()
      fadeInfo.endAlpha = targetAlpha

      fadeInfo.finishedFunc = function(finishedArg1)
        if finishedArg1:GetName() == debugFrameName then print("Fade out finished", finishedArg1:GetName(), targetAlpha) end
        frame:SetAlpha(1)
        ConditionalSetIgnoreParentAlpha(finishedArg1, false)
        if targetAlpha == 0 then
          ConditionalHide(finishedArg1)
        end
      end

    -- Frame was already adhering to parent alpha.
    -- We are not changing it.
    else
      fadeInfo.startAlpha = frame:GetAlpha()
      fadeInfo.endAlpha = frame:GetAlpha()
    end

  end

  -- if frame:GetName() == debugFrameName then print("Starting fade with", fadeInfo.startAlpha, fadeInfo.endAlpha, fadeInfo.mode) end
  UIFrameFade(frame, fadeInfo)

end


local function FadeInFrame(frame, duration, enteringCombat)

  if not frame then return end

  -- Prevent callback functions of currently active timers.
  UIFrameFadeRemoveFrame(frame)

  -- Only do something if we have touched this frame before.
  if frame.ludius_shownBeforeFadeOut == nil and frame.ludius_alphaBeforeFadeOut == nil and frame.ludius_ignoreParentAlphaBeforeFadeOut == nil then return end

  -- if frame:GetName() == debugFrameName then print("FadeInFrame", frame:GetName()) end


  if enteringCombat then
    -- When entering combat we have to show protected frames, which cannot be shown any more during combat.
    if frame:IsProtected() then
      ConditionalShow(frame)
    end
    -- But we do not yet do the fade in.
    return
  else
    ConditionalShow(frame)
  end


  -- To use UIFrameFade() which is the same as UIFrameFadeOut, but with a callback function.
  local fadeInfo = {}
  fadeInfo.mode = "IN"
  fadeInfo.timeToFade = duration
  fadeInfo.finishedArg1 = frame
  fadeInfo.finishedFunc = function(finishedArg1)
      finishedArg1.ludius_alphaBeforeFadeOut = nil
      finishedArg1.ludius_alphaAfterFadeOut = nil
    end


  -- Frame should henceforth ignore parent alpha.
  if frame.ludius_ignoreParentAlphaBeforeFadeOut == true then

    -- Frame was adhering to parent alpha before.
    -- Start the fade with UIParent's current alpha.
    if not frame:IsIgnoringParentAlpha() then
      fadeInfo.startAlpha = UIParent:GetAlpha()
    -- Frame was already ignoring parent alpha before.
    else
      fadeInfo.startAlpha = frame:GetAlpha()
    end
    fadeInfo.endAlpha = frame.ludius_alphaBeforeFadeOut

    ConditionalResetIgnoreParentAlpha(frame)

  -- Frame should henceforth adhere to parent alpha.
  elseif frame.ludius_ignoreParentAlphaBeforeFadeOut == false then

    -- Frame was ignoring parent alpha before.
    -- Start the fade with the frame's alpha, fade to UIParent's target alpha
    -- (which is always 1 when we fade the UI back in) and only then unset
    -- ignore parent alpha.
    if frame:IsIgnoringParentAlpha() then
      fadeInfo.startAlpha = frame:GetAlpha()
      fadeInfo.endAlpha = 1

      fadeInfo.finishedFunc = function(finishedArg1)
        ConditionalResetIgnoreParentAlpha(finishedArg1)
        finishedArg1.ludius_alphaBeforeFadeOut = nil
        finishedArg1.ludius_alphaAfterFadeOut = nil
      end

    -- Frame was already adhering to parent alpha.
    -- We are not changing it.
    else
      fadeInfo.startAlpha = frame:GetAlpha()
      fadeInfo.endAlpha = frame:GetAlpha()
    end

  -- No stored value in ludius_ignoreParentAlphaBeforeFadeOut.
  else
    fadeInfo.startAlpha = frame:GetAlpha()
    fadeInfo.endAlpha = frame.ludius_alphaBeforeFadeOut or frame:GetAlpha()
  end

  -- if frame:GetName() == debugFrameName then print("Starting fade with", fadeInfo.startAlpha, fadeInfo.endAlpha, fadeInfo.mode) end

  UIFrameFade(frame, fadeInfo)

  -- We can do this always when fading in.
  frame.ludius_fadeout = nil
  SetMouseOverAlpha(frame)

end



Addon.HideUI = function(fadeOutTime, config)

  -- print("HideUI", fadeOutTime)

  -- Remember that the UI is faded.
  Addon.uiHiddenTime = GetTime()

  if config.hideFrameRate then
    FadeOutFrame(FramerateLabel, fadeOutTime, true, config.UIParentAlpha)
    FadeOutFrame(FramerateText, fadeOutTime, true, config.UIParentAlpha)
  end

  AlertFramesSetIgnoreParentAlpha(config.keepAlertFrames)

  FadeOutFrame(CovenantRenownToast, fadeOutTime, config.keepAlertFrames, config.keepAlertFrames and 1 or config.UIParentAlpha)

  FadeOutFrame(MinimapCluster, fadeOutTime, config.keepMinimap, config.keepMinimap and 1 or config.UIParentAlpha)

  FadeOutFrame(GameTooltip, fadeOutTime, config.keepTooltip, config.keepTooltip and 1 or config.UIParentAlpha)
  FadeOutFrame(AceGUITooltip, fadeOutTime, config.keepTooltip, config.keepTooltip and 1 or config.UIParentAlpha)
  FadeOutFrame(AceConfigDialogTooltip, fadeOutTime, config.keepTooltip, config.keepTooltip and 1 or config.UIParentAlpha)

  FadeOutFrame(ChatFrame1, fadeOutTime, config.keepChatFrame, config.keepChatFrame and 1 or config.UIParentAlpha)
  FadeOutFrame(ChatFrame1Tab, fadeOutTime, config.keepChatFrame, config.keepChatFrame and 1 or config.UIParentAlpha)
  FadeOutFrame(ChatFrame1EditBox, fadeOutTime, config.keepChatFrame, config.keepChatFrame and 1 or config.UIParentAlpha)

  if GwChatContainer1 then
    FadeOutFrame(GwChatContainer1, fadeOutTime, config.keepChatFrame, config.keepChatFrame and 1 or config.UIParentAlpha)
  end


  if BT4StatusBarTrackingManager then
    FadeOutFrame(BT4StatusBarTrackingManager, fadeOutTime, config.keepTrackingBar, config.keepTrackingBar and config.trackingBarAlpha or config.UIParentAlpha)
  else
    FadeOutFrame(StatusTrackingBarManager, fadeOutTime, config.keepTrackingBar, config.keepTrackingBar and config.trackingBarAlpha or config.UIParentAlpha)
  end

  if GwExperienceFrame then
    FadeOutFrame(GwExperienceFrame, fadeOutTime, config.keepTrackingBar, config.keepTrackingBar and config.trackingBarAlpha or config.UIParentAlpha)
  end



  -- These frames are not adhering to UIParent's alpha. So we have to set their alpha manually.
  -- This is done by setting their ignore-parent-alpha to true and fading to UIParent's alpha.

  for i = 1, 4, 1 do
    if _G["PartyMemberFrame" .. i] then
      FadeOutFrame(_G["PartyMemberFrame" .. i .. "NotPresentIcon"], fadeOutTime, true, config.UIParentAlpha)
      FadeOutFrame(_G["PartyMemberFrame" .. i], fadeOutTime, true, config.UIParentAlpha)
    end
  end

  for i = 1, GetNumGroupMembers(), 1 do
    if _G["CompactRaidFrame" .. i] then
      FadeOutFrame(_G["CompactRaidFrame" .. i .. "Background"], fadeOutTime, true, config.UIParentAlpha)
      FadeOutFrame(_G["CompactRaidFrame" .. i .. "HorizTopBorder"], fadeOutTime, true, config.UIParentAlpha)
      FadeOutFrame(_G["CompactRaidFrame" .. i .. "HorizBottomBorder"], fadeOutTime, true, config.UIParentAlpha)
      FadeOutFrame(_G["CompactRaidFrame" .. i .. "VertLeftBorder"], fadeOutTime, true, config.UIParentAlpha)
      FadeOutFrame(_G["CompactRaidFrame" .. i .. "VertRightBorder"], fadeOutTime, true, config.UIParentAlpha)
      FadeOutFrame(_G["CompactRaidFrame" .. i], fadeOutTime, true, config.UIParentAlpha)
    end
  end



  -- Non-configurable frames that we just want to hide in case UIParentAlpha is 0.

  FadeOutFrame(QuickJoinToastButton, fadeOutTime, false, config.UIParentAlpha)
  FadeOutFrame(PlayerFrame, fadeOutTime, false, config.UIParentAlpha)
  FadeOutFrame(PetFrame, fadeOutTime, false, config.UIParentAlpha)
  FadeOutFrame(TargetFrame, fadeOutTime, false, config.UIParentAlpha)
  FadeOutFrame(BuffFrame, fadeOutTime, false, config.UIParentAlpha)
  FadeOutFrame(DebuffFrame, fadeOutTime, false, config.UIParentAlpha)


  if Bartender4 then

    FadeOutFrame(BT4Bar1, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4Bar2, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4Bar3, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4Bar4, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4Bar5, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4Bar6, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4Bar7, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4Bar8, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4Bar9, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4Bar10, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4BarBagBar, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4BarMicroMenu, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4BarStanceBar, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(BT4BarPetBar, fadeOutTime, false, config.UIParentAlpha)

  else

    FadeOutFrame(ExtraActionBarFrame, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(MainMenuBarArtFrame, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(MainMenuBarVehicleLeaveButton, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(MicroButtonAndBagsBar, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(MultiCastActionBarFrame, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(PetActionBarFrame, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(PossessBarFrame, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(StanceBarFrame, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(MultiBarRight, fadeOutTime, false, config.UIParentAlpha)
    FadeOutFrame(MultiBarLeft, fadeOutTime, false, config.UIParentAlpha)

  end


  if Addon.frameShowTimer then LibStub("AceTimer-3.0"):CancelTimer(Addon.frameShowTimer) end


end




-- If enteringCombat we only show the hidden frames (which cannot be shown
-- during combat lockdown). But we skip the SetIgnoreParentAlpha(false).
-- This can be done when the intended ShowUI() is called.
Addon.ShowUI = function(fadeInTime, enteringCombat)

  -- print("ShowUI", fadeInTime, enteringCombat)

  -- Only do something once per closing.
  if Addon.uiHiddenTime == 0 then return end

  if not enteringCombat then
    Addon.uiHiddenTime = 0
  end

  FadeInFrame(FramerateLabel, fadeInTime, enteringCombat)
  FadeInFrame(FramerateText, fadeInTime, enteringCombat)

  for i = 1, 4, 1 do
    if _G["PartyMemberFrame" .. i] then

      FadeInFrame(_G["PartyMemberFrame" .. i], fadeInTime, enteringCombat)
      FadeInFrame(_G["PartyMemberFrame" .. i .. "NotPresentIcon"], fadeInTime, enteringCombat)

    end
  end

  for i = 1, GetNumGroupMembers(), 1 do
    if _G["CompactRaidFrame" .. i] then

      FadeInFrame(_G["CompactRaidFrame" .. i], fadeInTime, enteringCombat)
      FadeInFrame(_G["CompactRaidFrame" .. i .. "Background"], fadeInTime, enteringCombat)
      FadeInFrame(_G["CompactRaidFrame" .. i .. "HorizTopBorder"], fadeInTime, enteringCombat)
      FadeInFrame(_G["CompactRaidFrame" .. i .. "HorizBottomBorder"], fadeInTime, enteringCombat)
      FadeInFrame(_G["CompactRaidFrame" .. i .. "VertLeftBorder"], fadeInTime, enteringCombat)
      FadeInFrame(_G["CompactRaidFrame" .. i .. "VertRightBorder"], fadeInTime, enteringCombat)

    end
  end


  FadeInFrame(QuickJoinToastButton, fadeInTime, enteringCombat)
  FadeInFrame(PlayerFrame, fadeInTime, enteringCombat)
  FadeInFrame(PetFrame, fadeInTime, enteringCombat)
  FadeInFrame(TargetFrame, fadeInTime, enteringCombat)
  FadeInFrame(BuffFrame, fadeInTime, enteringCombat)
  FadeInFrame(DebuffFrame, fadeInTime, enteringCombat)


  if Bartender4 then

    FadeInFrame(BT4Bar1, fadeInTime, enteringCombat)
    FadeInFrame(BT4Bar2, fadeInTime, enteringCombat)
    FadeInFrame(BT4Bar3, fadeInTime, enteringCombat)
    FadeInFrame(BT4Bar4, fadeInTime, enteringCombat)
    FadeInFrame(BT4Bar5, fadeInTime, enteringCombat)
    FadeInFrame(BT4Bar6, fadeInTime, enteringCombat)
    FadeInFrame(BT4Bar7, fadeInTime, enteringCombat)
    FadeInFrame(BT4Bar8, fadeInTime, enteringCombat)
    FadeInFrame(BT4Bar9, fadeInTime, enteringCombat)
    FadeInFrame(BT4Bar10, fadeInTime, enteringCombat)
    FadeInFrame(BT4BarBagBar, fadeInTime, enteringCombat)
    FadeInFrame(BT4BarMicroMenu, fadeInTime, enteringCombat)
    FadeInFrame(BT4BarStanceBar, fadeInTime, enteringCombat)
    FadeInFrame(BT4BarPetBar, fadeInTime, enteringCombat)

    -- Fade in the (possibly only partially) faded status bar.
    FadeInFrame(BT4StatusBarTrackingManager, fadeInTime, enteringCombat)

  else

    FadeInFrame(ExtraActionBarFrame, fadeInTime, enteringCombat)
    FadeInFrame(MainMenuBarArtFrame, fadeInTime, enteringCombat)
    FadeInFrame(MainMenuBarVehicleLeaveButton, fadeInTime, enteringCombat)
    FadeInFrame(MicroButtonAndBagsBar, fadeInTime, enteringCombat)
    FadeInFrame(MultiCastActionBarFrame, fadeInTime, enteringCombat)
    FadeInFrame(PetActionBarFrame, fadeInTime, enteringCombat)
    FadeInFrame(PossessBarFrame, fadeInTime, enteringCombat)
    FadeInFrame(StanceBarFrame, fadeInTime, enteringCombat)
    FadeInFrame(MultiBarRight, fadeInTime, enteringCombat)
    FadeInFrame(MultiBarLeft, fadeInTime, enteringCombat)


    -- Fade in the (possibly only partially) faded status bar.
    FadeInFrame(StatusTrackingBarManager, fadeInTime, enteringCombat)

  end


  if GwExperienceFrame then
    -- Fade in the (possibly only partially) faded status bar.
    FadeInFrame(GwExperienceFrame, fadeInTime, enteringCombat)
  end


  FadeInFrame(CovenantRenownToast, fadeInTime, enteringCombat)

  FadeInFrame(MinimapCluster, fadeInTime, enteringCombat)

  FadeInFrame(GameTooltip, fadeInTime, enteringCombat)
  FadeInFrame(AceGUITooltip, fadeInTime, enteringCombat)
  FadeInFrame(AceConfigDialogTooltip, fadeInTime, enteringCombat)

  FadeInFrame(ChatFrame1, fadeInTime, enteringCombat)
  FadeInFrame(ChatFrame1Tab, fadeInTime, enteringCombat)
  FadeInFrame(ChatFrame1EditBox, fadeInTime, enteringCombat)

  if GwChatContainer1 then
    FadeInFrame(GwChatContainer1, fadeInTime, enteringCombat)
  end



  -- Cancel timers that may still be in progress.
  if Addon.frameShowTimer then LibStub("AceTimer-3.0"):CancelTimer(Addon.frameShowTimer) end

  if not enteringCombat then
    -- Reset the IgnoreParentAlpha after the UI fade-in is finished.
    Addon.frameShowTimer = LibStub("AceTimer-3.0"):ScheduleTimer(function()
      AlertFramesResetIgnoreParentAlpha()
    end, fadeInTime)
  end


end





