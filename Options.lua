---------------
-- LIBRARIES --
---------------
local LibCamera = LibStub("LibCamera-1.0")

-------------
-- GLOBALS --
-------------
assert(DynamicCam)
DynamicCam.Options = DynamicCam:NewModule("Options", "AceEvent-3.0")


------------
-- LOCALS --
------------
local function ScriptEqual(customScript, defaultScript)
    if (customScript == "" and defaultScript == nil) or customScript == defaultScript then return true end
end


local function EventsEqual(customEvents, defaultEvents)
    local customEventsCheck = {}
    local defaultEventsCheck = {}

    for k, v in pairs(customEvents) do
        customEventsCheck[v] = true
    end

    for k, v in pairs(defaultEvents) do
        if not customEventsCheck[v] then
            return false
        end
        defaultEventsCheck[v] = true
    end

    for k, v in pairs(customEvents) do
        if not defaultEventsCheck[v] then
            return false
        end
    end

    return true
end



local Options = DynamicCam.Options
local _
local S, SID
local copiedSituationID
local exportName, exportAuthor

local welcomeMessage = [[Hello and welcome to DynamicCam!

We're glad that you're here and we hope that you have fun with the addon.

If you find a problem or want to make a suggestion, please, please leave a note in the Curse comments or use the Issues on GitHub. If you'd like to contribute, also feel free to open a pull request there.

Some handy slash commands:
    `/dynamiccam` or `/dc` will open this menu
    `/zoominfo` or `/zi` will print out the current zoom
    `/saveview #` or `/sv #` will save to the specified view slot (where # is a number between 2 and 5)

    The following slash commands will also accept a time:
        `/zoom #` will zoom to that zoom level
        `/yaw #` will yaw the camera left/right by that number of degrees
        `/pitch #` will pitch the camera up/down by that number of degrees

        Example:
            `/zoom 5 5` will zoom to 5 over 5 seconds.
    ]]


local easingValues = {
    Linear = "Linear",
    InQuad = "In Quadratic",
    OutQuad = "Out Quadratic",
    InOutQuad = "In/Out Quadratic",
    OutInQuad = "Out/In Quadratic",
    InCubic = "In Cubic",
    OutCubic = "Out Cubic",
    InOutCubic = "In/Out Cubic",
    OutInCubic = "Out/In Cubic",
    InQuart = "In Quartic",
    OutQuart = "Out Quartic",
    InOutQuart = "In/Out Quartic",
    OutInQuart = "Out/In Quartic",
    InQuint = "In Quintic",
    OutQuint = "Out Quintic",
    InOutQuint = "In/Out Quintic",
    OutInQuint = "Out/In Quintic",
    InSine = "In Sine",
    OutSine = "Out Sine",
    InOutSine = "In/Out Sine",
    OutInSine = "Out/In Sine",
    InExpo = "In Exponent",
    OutExpo = "Out Exponent",
    InOutExpo = "In/Out Exponent",
    OutInExpo = "Out/In Exponent",
    InCirc = "In Circular",
    OutCirc = "Out Circular",
    InOutCirc = "In/Out Circular",
    OutInCirc = "Out/In Circular",
}








local general = {
    type = "group",
    name = "General",
    order = 1,
    args = {
        messageGroup = {
            type = "group",
            name = "Welcome!",
            order = 2,
            inline = true,
            args = {
                message = {
                    type = "description",
                    name = welcomeMessage,
                },
            }
        },

        zoomRestoreSettingGroup = {
            type = "group",
            name = "Restore Zoom",
            order = 0,
            inline = true,
            args = {
                zoomRestoreSettingDescription = {
                    type = "description",
                    name = "When you leave a situation (or leave the default of no situation being active), the current zoom level is temporarily stored, such that it can be restored once you return to that situation. These are the options:\n\nNever: The zoom is never restored. I.e. when you enter a situation, no stored zoom is taken into account, but the zoom setting from the situation's options (if any) is applied.\n\nAlways: When entering a situation, the stored zoom (if any) is always restored.\n\nAdaptive: This only restores the zoom level under certain circumstances. E.g. only when returning to the same situation you came from or when the stored zoom fulfills the criteria of the situation's \"in\", \"out\" or \"range\" zoom settings.",
                    order = 0,
                },
                zoomRestoreSetting = {
                    type = "select",
                    name = "",
                    order = 1,
                    get = function() return DynamicCam.db.profile.zoomRestoreSetting end,
                    set = function(_, newValue) DynamicCam.db.profile.zoomRestoreSetting = newValue end,
                    values = {["adaptive"] = "Adaptive", ["always"] = "Always", ["never"] = "Never"},
                },
            },
        },

    },
}



-- We want to use the same CreateSettingsTab() function for the
-- standard settings and situation settings. Hence we need this function
-- to return the appropriate table.
function DynamicCam:GetSettingsTable(situationId)
    if situationId then
        return self.db.profile.situations[situationId].situationSettings
    else
        return self.db.profile.standardSettings
    end
end


-- For the get functions of the options: if a situation has no setting,
-- we want to show the standard value.
function DynamicCam:GetSettingsTableValue(situationId, index1, index2)

    -- Is this a request for a standard or situation setting?
    local settingsTable = self:GetSettingsTable(situationId)

    -- Is this a request for the cvars sub table?
    if index1 == "cvars" and index2 then
        if settingsTable.cvars[index2] ~= nil then
            return settingsTable.cvars[index2]
        else
            return self.db.profile.standardSettings.cvars[index2]
        end
    else
        if settingsTable[index1] ~= nil then
            return settingsTable[index1]
        else
            return self.db.profile.standardSettings[index1]
        end
    end
end



local function CreateSettingsTab(tabOrder, forSituations)

    return {

        type = "group",
        name = function()
                   if not forSituations then return "Standard Settings"
                   else return "Situation Settings" end
               end,
        order = tabOrder,
        args = {

            help = {
                type = "description",
                name = function()

                          if not forSituations then

                              local text = "These standard settings are applied when either no situation is active or when the active situation has no own settings set up to override the standard settings."

                              if SID == DynamicCam.currentSituationID then
                                  text = text .. "|cFF00FF00 You are currently in the situation \"" .. S.name .. "\". If this is overriding a standard setting, you will not see the effect of changing the respective standard setting right now.|r"
                              end

                              return text .. "\n\n"

                          else

                              local text = "These situation settings are applied when a situation is active and override the standard settings."
                              return text .. "\n\n"

                          end

                       end,
                order = 0,
            },


            zoomGroup = {
                type = "group",
                name = "Mouse Zoom",
                order = 1,
                args = {

                    cameraDistanceMaxFactor = {
                        type = "range",
                        name = "Maximum Camera Distance",
                        desc = "How many yards the camera can zoom away from your character.\n|cff909090cvar: cameraDistanceMaxZoomFactor|r",
                        order = 1,
                        width = "full",
                        min = 15,
                        max = 39,
                        step = 0.5,
                        get = function() return 15 * DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "cameraDistanceMaxZoomFactor") end,
                        set = function(_, newValue)
                                  DynamicCam:GetSettingsTable(forSituations and SID).cvars["cameraDistanceMaxZoomFactor"] = newValue/15
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank1 = {
                        type = "description",
                        name = " ",
                        order = 1.1,
                    },

                    cameraZoomSpeed = {
                        type = "range",
                        name = "Camera Zoom Speed",
                        desc = "How fast the camera can zoom.\n|cff909090cvar: cameraZoomSpeed|r",
                        order = 2,
                        width = "full",
                        min = 1,
                        max = 50,
                        step = 0.5,
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "cameraZoomSpeed") end,
                        set = function(_, newValue)
                                  DynamicCam:GetSettingsTable(forSituations and SID).cvars["cameraZoomSpeed"] = newValue
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank2 = {
                        type = "description",
                        name = " ",
                        order = 2.1,
                    },

                    addIncrementsAlways = {
                        type = "range",
                        name = "Zoom Increments",
                        desc = "How many yards the camera should travel for each \'tick\' of the mouse wheel.",
                        order = 3,
                        width = "full",
                        min = 0.05,
                        max = 10,
                        step = 0.05,
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "reactiveZoomAddIncrementsAlways") + 1 end,
                        set = function(_, newValue) DynamicCam:GetSettingsTable(forSituations and SID).reactiveZoomAddIncrementsAlways = newValue - 1 end,
                    },
                    blank3 = {
                        type = "description",
                        name = "\n\n",
                        order = 3.1,
                    },

                    reactiveZoomToggle = {
                        type = "toggle",
                        name = "Use Reactive Zoom",
                        order = 4,
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "reactiveZoomEnabled") end,
                        set = function(_, newValue)
                                  DynamicCam:GetSettingsTable(forSituations and SID).reactiveZoomEnabled = newValue
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },

                    reactiveZoomGroup = {
                        type = "group",
                        name = "",
                        disabled = function() return not DynamicCam:GetSettingsTableValue(forSituations and SID, "reactiveZoomEnabled") end,
                        order = 5,
                        inline = true,
                        args = {

                            addIncrements = {
                                type = "range",
                                name = "Quick-Zoom Additional Increments",
                                desc = "How many yards per mouse wheel tick should be added when quick-zooming.",
                                order = 1,
                                width = "full",
                                min = 0,
                                max = 10,
                                step = 0.1,
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "reactiveZoomAddIncrements") end,
                                set = function(_, newValue) DynamicCam:GetSettingsTable(forSituations and SID).reactiveZoomAddIncrements = newValue end,
                            },
                            blank1 = {
                                type = "description",
                                name = " ",
                                order = 1.1,
                            },

                            incAddDifference = {
                                type = "range",
                                name = "Quick-Zoom Enter Threshold",
                                desc = "How many yards the \"Reactive Zoom Target\" and the \"Actual Zoom Value\" have to be apart to enter quick-zooming.",
                                order = 2,
                                width = "full",
                                min = 0.1,
                                max = 5,
                                step = 0.1,
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "reactiveZoomIncAddDifference") end,
                                set = function(_, newValue) DynamicCam:GetSettingsTable(forSituations and SID).reactiveZoomIncAddDifference = newValue end,
                            },
                            blank2 = {
                                type = "description",
                                name = " ",
                                order = 2.1,
                            },

                            maxZoomTime = {
                                type = "range",
                                name = "Maximum Zoom Time",
                                desc = "The maximum time the camera should take to make \"Actual Zoom Value\" equal to \"Reactive Zoom Target\".",
                                order = 3,
                                width = "full",
                                min = 0.1,
                                max = 5,
                                step = 0.05,
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "reactiveZoomMaxZoomTime") end,
                                set = function(_, newValue) DynamicCam:GetSettingsTable(forSituations and SID).reactiveZoomMaxZoomTime = newValue end,
                            },
                            blank3 = {
                                type = "description",
                                name = "\n\n",
                                order = 3.1,
                            },

                        },
                    },

                    reactiveZoomDescriptionGroup = {
                        type = "group",
                        name = "Help",
                        order = 6,
                        inline = true,
                        args = {

                            export = {
                                type = "execute",
                                name = "Toggle Visual Aid",
                                func = function() DynamicCam:ToggleRZVA() end,
                                order = 1,
                                width = "full",
                            },
                            blank1 = {
                                type = "description",
                                name = " ",
                                order = 1.1,
                            },

                            reactiveZoomDescription = {
                                type = "description",
                                name = "With DynamicCam's Reactive Zoom the mouse wheel controls the so called \"Reactive Zoom Target\". Whenever \"Reactive Zoom Target\" and the \"Actual Zoom Value\" are different, DynamicCam changes the \"Actual Zoom Value\" until it matches \"Reactive Zoom Target\" again.\n\nHow fast this zoom change is happening depends on \"Camera Zoom Speed\" and \"Maximum Zoom Time\". If \"Maximum Zoom Time\" is set low, the zoom change will always be executed fast, regardless of the \"Camera Zoom Speed\" setting. To achieve a slower zoom change, however, you must set \"Maximum Zoom Time\" to a higher value and \"Camera Zoom Speed\" to a lower value.\n\nTo enable faster zooming with faster mouse wheel movement, there is \"Quick-Zoom\". While \"Reactive Zoom Target\" is further away from \"Actual Zoom Value\" than the \"Quick-Zoom Enter Threshold\", the amount of \"Quick-Zoom Additional Increments\" is added to every mouse wheel tick.\n\nTo get a good feeling of how this works, you can toggle the visual aid while finding your ideal settings. You can also freely move this graph by dragging it.",
                                order = 2,
                            },
                        },
                    },
                },
            },


            mouseLookGroup = {
                type = "group",
                name = "Mouse Look",
                order = 2,
                args = {

                    cameraYawMoveSpeed = {
                        type = "range",
                        name = "Horizontal Speed",
                        desc = "How much the camera yaws horizontally when in mouse look mode.\n|cff909090cvar: cameraYawMoveSpeed|r",
                        order = 1,
                        width = "full",
                        min = 1,
                        max = 360,
                        step = 1,
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "cameraYawMoveSpeed") end,
                        set = function(_, newValue)
                                  DynamicCam:GetSettingsTable(forSituations and SID).cvars["cameraYawMoveSpeed"] = newValue
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank1 = {
                        type = "description",
                        name = " ",
                        order = 1.1,
                    },

                    cameraPitchMoveSpeed = {
                        type = "range",
                        name = "Vertical Speed",
                        desc = "How much the camera pitches vertically when in mouse look mode.\n|cff909090cvar: cameraPitchMoveSpeed|r",
                        order = 2,
                        width = "full",
                        min = 1,
                        max = 360,
                        step = 1,
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "cameraPitchMoveSpeed") end,
                        set = function(_, newValue)
                                  DynamicCam:GetSettingsTable(forSituations and SID).cvars["cameraPitchMoveSpeed"] = newValue
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank2 = {
                        type = "description",
                        name = "\n\n",
                        order = 2.1,
                    },

                    mouseLookDescriptionGroup = {
                        type = "group",
                        name = "Help",
                        order = 3,
                        inline = true,
                        args = {

                            yawPitchDescription = {
                                type = "description",
                                name = "How much the camera moves when you move the mouse in \"mouse look\" mode; i.e. while the left or right mouse button is pressed.\n\nThe \"Mouse Look Speed\" slider of WoW's default interface settings controls horizontal and vertical speed at the same time: automatically setting horizontal speed to 2 x vertical speed. DynamicCam overrides this and allows you a more customized setup.",
                            },
                        },
                    },
                },
            },


            shoulderOffsetGroup = {
                type = "group",
                name = "Horizontal Offset",
                order = 3,
                args = {

                    cameraOverShoulderGroup = {
                        type = "group",
                        name = "Camera Over Shoulder Offset",
                        order = 1,
                        inline = true,
                        args = {

                            cameraOverShoulderDescription = {
                                type = "description",
                                name = "Positions the camera left or right from your character.\n|cff909090cvar: test_cameraOverShoulder|r\n\nWhen you are selecting your own character, WoW automatically switches to an offset of zero. There is nothing we can do about this. We also cannot do anything about offset jerks that may occur upon camera-to-wall collisions. A workaround is to use little to no offset while indoors.\n\nFurthermore, WoW strangely applies the offest differntly depending on player model or mount. If you prefer a constant offset, Ludius is working on another addon (cameraOverShoulder_Fix) to resolve this.",
                                order = 0,
                            },

                            cameraOverShoulder = {
                                type = "range",
                                name = "",
                                order = 1,
                                width = "full",
                                min = -15,
                                max = 15,
                                step = 0.1,
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraOverShoulder") end,
                                set = function(_, newValue)
                                          DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraOverShoulder"] = newValue
                                          Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                                      end,
                            },
                        },
                    },
                    blank1 = {
                        type = "description",
                        name = " ",
                        order = 1.1,
                    },

                    shoulderOffsetZoomGroup = {
                        type = "group",
                        name = "Adjust shoulder offset according to zoom level",
                        order = 2,
                        inline = true,
                        args = {


                            shoulderOffsetZoomEnabled = {
                                type = "toggle",
                                name = "Enable",
                                order = 1,
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "shoulderOffsetZoomEnabled") end,
                                set = function(_, newValue)
                                        DynamicCam:GetSettingsTable(forSituations and SID).shoulderOffsetZoomEnabled = newValue
                                        DynamicCam:ZoomSlash(GetCameraZoom() .. " " .. 0)
                                    end,

                            },
                            shoulderOffsetZoomLowerBound = {
                                type = "range",
                                name = "No offset when below this zoom level:",
                                order = 2,
                                width = "full",
                                desc = "When the camera is closer than this zoom level, the offset has reached zero.",
                                min = 0.8,
                                max = 39,
                                step = 0.1,
                                disabled = function() return not DynamicCam:GetSettingsTableValue(forSituations and SID, "shoulderOffsetZoomEnabled") end,
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "shoulderOffsetZoomLowerBound") end,
                                set = function(_, newValue)
                                        DynamicCam:GetSettingsTable(forSituations and SID).shoulderOffsetZoomLowerBound = newValue
                                        if DynamicCam:GetSettingsTable(forSituations and SID).shoulderOffsetZoomUpperBound < newValue then
                                            DynamicCam:GetSettingsTable(forSituations and SID).shoulderOffsetZoomUpperBound = newValue
                                        end
                                        DynamicCam:ZoomSlash(GetCameraZoom() .. " " .. 0)
                                    end,

                            },
                            blank2 = {
                                type = "description",
                                name = " ",
                                order = 2.1,
                            },

                            shoulderOffsetZoomUpperBound = {
                                type = "range",
                                name = "Real offset when above this zoom level:",
                                order = 3,
                                width = "full",
                                desc = "When the camera is further away than this zoom level, the offset has reached its set value.",
                                min = 0.8,
                                max = 39,
                                step = 0.1,
                                disabled = function() return not DynamicCam:GetSettingsTableValue(forSituations and SID, "shoulderOffsetZoomEnabled") end,
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "shoulderOffsetZoomUpperBound") end,
                                set = function(_, newValue)
                                        DynamicCam:GetSettingsTable(forSituations and SID).shoulderOffsetZoomUpperBound = newValue
                                        if DynamicCam:GetSettingsTable(forSituations and SID).shoulderOffsetZoomLowerBound > newValue then
                                            DynamicCam:GetSettingsTable(forSituations and SID).shoulderOffsetZoomLowerBound = newValue
                                        end
                                        DynamicCam:ZoomSlash(GetCameraZoom() .. " " .. 0)
                                    end,

                            },

                            blank3 = {
                                type = "description",
                                name = " ",
                                order = 3.1,
                            },

                            shoulderOffsetZoomDescription = {
                                type = "description",
                                name = "Make the shoulder offset gradually transition to zero while zooming in. The two sliders define between what zoom levels this transition takes place.",
                                order = 4,
                            },


                        },
                    },
                },
            },


            pitchGroup = {
                type = "group",
                name = "Vertical Pitch",
                order = 4,
                args = {

                    cameraDynamicPitch = {
                        type = "toggle",
                        name = "Enable",
                        order = 1,
                        width = "full",
                        desc = "|cff909090cvar: test_cameraDynamicPitch|r",
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraDynamicPitch") == 1 end,
                        set = function(_, newValue)
                                  if newValue then
                                      DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraDynamicPitch"] = 1
                                  else
                                      DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraDynamicPitch"] = 0
                                  end
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank1 = {
                        type = "description",
                        name = " ",
                        order = 1.1,
                    },

                    baseFovPad = {
                        type = "range",
                        name = "Pitch (on ground)",
                        order = 2,
                        width = "full",
                        desc = "|cff909090cvar: test_cameraDynamicPitch\nBaseFovPad|r",
                        min = 0,
                        max = 0.99,
                        step = 0.01,
                        disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraDynamicPitch") == 0 end,
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraDynamicPitchBaseFovPad") end,
                        set = function(_, newValue)
                                  DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraDynamicPitchBaseFovPad"] = newValue
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank2 = {
                        type = "description",
                        name = " ",
                        order = 2.1,
                    },

                    baseFovPadFlying = {
                        type = "range",
                        name = "Pitch (flying)",
                        order = 3,
                        width = "full",
                        desc = "|cff909090cvar: test_cameraDynamicPitch\nBaseFovPadFlying|r",
                        min = 0,
                        max = 1,
                        step = 0.01,
                        disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraDynamicPitch") == 0 end,
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraDynamicPitchBaseFovPadFlying") end,
                        set = function(_, newValue)
                                  DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraDynamicPitchBaseFovPadFlying"] = newValue
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank3 = {
                        type = "description",
                        name = "\n\n",
                        order = 3.1,
                    },

                    baseFovPadDownScale = {
                        type = "range",
                        name = "Down Scale",
                        order = 4,
                        width = "full",
                        desc = "|cff909090cvar: test_cameraDynamicPitch\nBaseFovPadDownScale|r",
                        min = 0,
                        max = 1,
                        step = 0.01,
                        disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraDynamicPitch") == 0 end,
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraDynamicPitchBaseFovPadDownScale") end,
                        set = function(_, newValue)
                                  DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraDynamicPitchBaseFovPadDownScale"] = newValue
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank4 = {
                        type = "description",
                        name = "\n\n",
                        order = 4.1,
                    },

                    smartPivotCutoffDist = {
                        type = "range",
                        name = "Smart Pivot Cutoff Distance",
                        order = 5,
                        width = "full",
                        desc = "|cff909090cvar: test_cameraDynamicPitch\nSmartPivotCutoffDist|r",
                        min = 0,
                        max = 100,
                        softMin = 0,
                        softMax = 39,
                        step = 0.5,
                        disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraDynamicPitch") == 0 end,
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraDynamicPitchSmartPivotCutoffDist") end,
                        set = function(_, newValue)
                                DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraDynamicPitchSmartPivotCutoffDist"] = newValue
                                Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                            end,
                    },
                    blank5 = {
                        type = "description",
                        name = " ",
                        order = 5.1,
                    },

                    pitchDescriptionGroup = {
                        type = "group",
                        name = "Help",
                        order = 6,
                        inline = true,
                        args = {

                            pitchDescription = {
                                type = "description",
                                name = "If the camera is pitched upwards (lower \"Pitch\" value), the \"Down Scale\" setting determines how much this comes into effect while looking at your character from above. Setting \"Down Scale\" to 0 nullifies the effect of an upwards pitch while looking from above. On the contrary, while you are not looking from above or if the camera is pitched downwards (greater \"Pitch\" value), the \"Down Scale\" setting has little to no effect.\n\nThus, you should first find your preferred \"Pitch\" setting while looking at your character from behind. Afterwards, if you have chosen an upwards pitch, find your preferred \"Down Scale\" setting while looking from above.\n\n\nWhen the camera collides with the ground, it normally performs an upwards pitch on the spot of the camera-to-ground collision. An alternative is that the camera moves closer to your character's feet while performing this pitch. The \"Smart Pivot Cutoff Distance\" setting determines the distance that the camera has to be inside of to do the latter. Setting it to 0 never moves the camera closer (WoW's default), whereas setting it to the maximum zoom distance of 39 always moves the camera closer.\n\n",
                            },
                        },
                    },
                },
            },


            targetFocusGroup = {
                type = "group",
                name = "Target Focus",
                order = 5,
                args = {

                    targetFocusEnemiesGroup = {
                        type = "group",
                        name = "Enemy Target",
                        order = 1,
                        inline = true,
                        args = {

                            targetFocusEnemyEnable = {
                                type = "toggle",
                                name = "Enable",
                                order = 1,
                                width = "full",
                                desc = "|cff909090cvar: test_cameraTargetFocus\nEnemyEnable|r",
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraTargetFocusEnemyEnable") == 1 end,
                                set = function(_, newValue)
                                          if newValue then
                                              DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraTargetFocusEnemyEnable"] = 1
                                          else
                                              DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraTargetFocusEnemyEnable"] = 0
                                          end
                                          Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                                      end,
                            },

                            targetFocusEnemyStrengthYaw = {
                                type = "range",
                                name = "Horizontal Strength",
                                order = 2,
                                width = "full",
                                desc = "|cff909090cvar: test_cameraTargetFocus\nEnemyStrengthYaw|r",
                                min = 0,
                                max = 1,
                                step = 0.05,
                                disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraTargetFocusEnemyEnable") == 0 end,
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraTargetFocusEnemyStrengthYaw") end,
                                set = function(_, newValue)
                                          DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraTargetFocusEnemyStrengthYaw"] = newValue
                                          Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                                      end,
                            },
                            blank2 = {
                                type = "description",
                                name = " ",
                                order = 2.1,
                            },

                            targetFocusEnemyStrengthPitch = {
                                type = "range",
                                name = "Vertical Strength",
                                order = 3,
                                width = "full",
                                desc = "|cff909090cvar: test_cameraTargetFocus\nEnemyStrengthPitch|r",
                                min = 0,
                                max = 1,
                                step = 0.05,
                                disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraTargetFocusEnemyEnable") == 0 end,
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraTargetFocusEnemyStrengthPitch") end,
                                set = function(_, newValue)
                                          DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraTargetFocusEnemyStrengthPitch"] = newValue
                                          Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                                      end,
                            },


                        },
                    },
                    blank1 = {
                        type = "description",
                        name = " ",
                        order = 1.1,
                    },


                    targetFocusNPCsGroup = {
                        type = "group",
                        name = "Interaction Target (NPCs)",
                        order = 2,
                        inline = true,
                        args = {

                            targetFocusInteractEnable = {
                                type = "toggle",
                                name = "Enable",
                                order = 1,
                                width = "full",
                                desc = "|cff909090cvar: test_cameraTargetFocus\nInteractEnable|r",
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraTargetFocusInteractEnable") == 1 end,
                                set = function(_, newValue)
                                          if newValue then
                                              DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraTargetFocusInteractEnable"] = 1
                                          else
                                              DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraTargetFocusInteractEnable"] = 0
                                          end
                                          Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                                      end,
                            },

                            targetFocusInteractStrengthYaw = {
                                type = "range",
                                name = "Horizontal Strength",
                                order = 2,
                                width = "full",
                                desc = "|cff909090cvar: test_cameraTargetFocus\nInteractStrengthYaw|r",
                                min = 0,
                                max = 1,
                                step = 0.05,
                                disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraTargetFocusInteractEnable") == 0 end,
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraTargetFocusInteractStrengthYaw") end,
                                set = function(_, newValue)
                                          DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraTargetFocusInteractStrengthYaw"] = newValue
                                          Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                                      end,
                            },
                            blank2 = {
                                type = "description",
                                name = " ",
                                order = 2.1,
                            },

                            targetFocusInteractStrengthPitch = {
                                type = "range",
                                name = "Vertical Strength",
                                order = 3,
                                width = "full",
                                desc = "|cff909090cvar: test_cameraTargetFocus\nInteractStrengthPitch|r",
                                min = 0,
                                max = 1,
                                step = 0.05,
                                disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraTargetFocusInteractEnable") == 0 end,
                                get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraTargetFocusInteractStrengthPitch") end,
                                set = function(_, newValue)
                                          DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraTargetFocusInteractStrengthPitch"] = newValue
                                          Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                                      end,
                            },

                        },
                    },
                    blank2 = {
                        type = "description",
                        name = " ",
                        order = 2.1,
                    },

                    targetFocusDescriptionGroup = {
                        type = "group",
                        name = "Help",
                        order = 3,
                        inline = true,
                        args = {
                            targetFocusDescription = {
                                type = "description",
                                name = "If enabled, the camera automatically tries to bring the target closer to the center of the screen. The strength determines the intensity of this effect.\n\nIf \"Enemy Target Focus\" and \"Interaction Target Focus\" are both enabled, there seems to be a strange bug with the latter: When interacting with an NPC for the first time, the camera smoothly moves to its new angle as expected. But when you leave the interaction, it snaps immediately into its previous angle. When you then start the interaction again, it snaps again to the new angle. This is repeatable whenever talking to a new NPCs: only the first transition is smooth, all following are immediate.\nA workaround, if you want to use both \"Enemy Target Focus\" and \"Interaction Target Focus\" is to only activate \"Enemy Target Focus\" for DynamicCam situations in which you need it and in which NPC interactions are unlikely (like Combat).",
                            },
                        },
                    },
                },
            },


            headTracking = {
                type = "group",
                name = "Head Tracking",
                order = 6,
                args = {

                    headTrackingEnable = {
                        type = "toggle",
                        name = "Enable",
                        order = 1,
                        width = "full",
                        desc = "|cff909090cvar: test_cameraHeadMovement\nStrength\n\nThis could also be used as a continuous value between 0 and 1, but it is just multiplied with StandingStrength and MovingStrength respectively. So there is really no need for another slider.|r",
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementStrength") == 1 end,
                        set = function(_, newValue)
                                  if newValue then
                                      DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraHeadMovementStrength"] = 1
                                  else
                                      DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraHeadMovementStrength"] = 0
                                  end
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank1 = {
                        type = "description",
                        name = " ",
                        order = 1.1,
                    },



                    standingStrength = {
                        type = "range",
                        order = 3,
                        width = "full",
                        name = "Strength (standing)",
                        desc = "|cff909090cvar: test_cameraHeadMovement\nStandingStrength|r",
                        min = 0,
                        max = 1,   -- No effect above 1.
                        step = 0.01,
                        disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementStrength") == 0 end,
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementStandingStrength") end,
                        set = function(_, newValue)
                                DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraHeadMovementStandingStrength"] = newValue
                                Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                            end,
                    },
                    blank3 = {
                        type = "description",
                        name = " ",
                        order = 3.1,
                    },
                    standingDampRate = {
                        type = "range",
                        order = 4,
                        width = "full",
                        name = "Inertia (standing)",
                        desc = "|cff909090cvar: test_cameraHeadMovement\nStandingDampRate|r",
                        min = 0,
                        max = 20,
                        step = 0.05,
                        disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementStrength") == 0 end,
                        get = function()
                                  -- Real minimum is 0.01, but makes the slider look odd.
                                  if DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementStandingDampRate") == 0.01 then
                                      return 0
                                  else
                                      return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementStandingDampRate")
                                  end
                              end,
                        set = function(_, newValue)
                                  -- Real minimum is 0.01, but makes the slider look odd.
                                  if newValue == 0 then newValue = 0.01 end
                                  DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraHeadMovementStandingDampRate"] = newValue
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank4 = {
                        type = "description",
                        name = "\n\n",
                        order = 4.1,
                    },



                    movingStrength = {
                        type = "range",
                        order = 5,
                        width = "full",
                        name = "Strength (moving)",
                        desc = "|cff909090cvar: test_cameraHeadMovement\nMovingStrength|r",
                        min = 0,
                        max = 1,   -- No effect above 1.
                        step = 0.01,
                        disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementStrength") == 0 end,
                        get = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementMovingStrength") end,
                        set = function(_, newValue)
                                DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraHeadMovementMovingStrength"] = newValue
                                Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                            end,
                    },
                    blank5 = {
                        type = "description",
                        name = " ",
                        order = 5.1,
                    },
                    movingDampRate = {
                        type = "range",
                        order = 6,
                        width = "full",
                        name = "Inertia (moving)",
                        desc = "|cff909090cvar: test_cameraHeadMovement\nMovingDampRate|r",
                        min = 0,
                        max = 20,
                        step = 0.05,
                        disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementStrength") == 0 end,
                        get = function()
                                  -- Real minimum is 0.01, but makes the slider look odd.
                                  if DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementMovingDampRate") == 0.01 then
                                      return 0
                                  else
                                      return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementMovingDampRate")
                                  end
                              end,
                        set = function(_, newValue)
                                  -- Real minimum is 0.01, but makes the slider look odd.
                                  if newValue == 0 then newValue = 0.01 end
                                  DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraHeadMovementMovingDampRate"] = newValue
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank6 = {
                        type = "description",
                        name = "\n\n",
                        order = 6.1,
                    },



                    firstPersonDampRate = {
                        type = "range",
                        order = 7,
                        width = "full",
                        name = "Inertia (first person)",
                        desc = "|cff909090cvar: test_cameraHeadMovement\nFirstPersonDampRate|r",
                        min = 0,
                        max = 20,
                        step = 0.05,
                        disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementStrength") == 0 end,
                        get = function()
                                  -- Real minimum is 0.01, but makes the slider look odd.
                                  if DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementFirstPersonDampRate") == 0.01 then
                                      return 0
                                  else
                                      return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementFirstPersonDampRate")
                                  end
                              end,
                        set = function(_, newValue)
                                  -- Real minimum is 0.01, but makes the slider look odd.
                                  if newValue == 0 then newValue = 0.01 end
                                  DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraHeadMovementFirstPersonDampRate"] = newValue
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank7 = {
                        type = "description",
                        name = "\n\n",
                        order = 7.1,
                    },


                    rangeScale = {
                        type = "range",
                        order = 8,
                        width = "full",
                        name = "Range Scale",
                        desc = "Camera distance beyond which head tracking is reduced or disabled. (See explanation below.)\n|cff909090cvar: test_cameraHeadMovement\nRangeScale (slider value transformed)|r",
                        min = 0,
                        max = 117,
                        step = 0.5,
                        disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementStrength") == 0 end,
                        get = function() return (DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementRangeScale")  * 3.25) + 0.1625 end,
                        set = function(_, newValue)
                                  newValue = (newValue - 0.1625) / 3.25
                                  DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraHeadMovementRangeScale"] = newValue
                                  Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                              end,
                    },
                    blank8 = {
                        type = "description",
                        name = "\n\n",
                        order = 8.1,
                    },

                    deadZone = {
                        type = "range",
                        order = 9,
                        width = "full",
                        name = "Dead Zone",
                        desc = "Radius of head movement not affecting the camera. (See explanation below.)\n|cff909090cvar: test_cameraHeadMovement\nDeadZone (slider value / 10)|r\n|cffe00000Requires /reload to come into effect!|r",
                        min = 0,
                        max = 10,
                        step = 0.05,
                        disabled = function() return DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementStrength") == 0 end,
                        get = function() return 10 * DynamicCam:GetSettingsTableValue(forSituations and SID, "cvars", "test_cameraHeadMovementDeadZone") end,
                        set = function(_, newValue)
                                DynamicCam:GetSettingsTable(forSituations and SID).cvars["test_cameraHeadMovementDeadZone"] = newValue / 10
                                Options:SendMessage("DC_BASE_CAMERA_UPDATED")
                            end,
                    },


                    headTrackingDescriptionGroup = {
                        type = "group",
                        name = "Help",
                        order = 10,
                        inline = true,
                        args = {
                            headTrackingDescription = {
                                type = "description",
                                name = "With head tracking enabled the camera follows the movement of your character's head. (While this can be a benefit for immersion, it may also cause nausea if you are prone to motion sickness.)\n\nThe \"Strength\" setting determines the intensity of this effect. Setting it to 0 disables head tracking. The \"Inertia\" setting determines how fast the camera reacts to head movements. Setting it to 0 also disables head tracking. The three cases \"standing\", \"moving\" and \"first person\" can be set up individually. There is no \"Strength\" setting for \"first person\" as it assumes the \"Strength\" settings of \"standing\" and \"moving\" respectively. If you want to enable or disable \"first person\" exclusively, use the \"Inertia\" sliders to disable the unwanted cases.\n\nWith the \"Range Scale\" setting you can set the camera distance beyond which head tracking is reduced or disabled. For example, with the slider set to 30 you will have no head tracking when the camera is more than 30 yards away from your character. However, there is a gradual transition from full head tracking to no head tracking, which starts at one third of the slider value. For example, with the slider value set to 30 you have full head tracking when the camera is closer than 10 yards. Beyond 10 yards, head tracking gradually decreases until it is completely gone beyond 30 yards. Hence, the slider's maximum value is 117 allowing for full head tracking at the maximum camera distance of 39 yards. (Hint: Use our \"Mouse Zoom\" visual aid to check the current camera distance while setting this up.)\n\nThe \"Dead Zone\" setting can be used to ignore smaller head movements. Setting it to 0 has the camera follow every slightest head movement, whereas setting it to a greater value results in it following only greater movements. Notice, that changing this setting apDynamicCamly only comes into effect after reloading the UI (type /reload into the console).",
                            },
                        },
                    },


                },
            },
        },

    }
end





local function CreateSituationSettingsTab(tabOrder)

    return {

        type = "group",
        name = "Situations",
        order = tabOrder,

        childGroups = "tab",

        args = {


            selectedSituation = {
                type = "select",
                name = "Selected Situation",
                desc = "Which situation you are editing",
                get = function() return SID end,
                set = function(_, newValue)
                        S = DynamicCam.db.profile.situations[newValue]
                        SID = newValue
                    end,
                values = function() return DynamicCam:GetSituationList() end,
                width = 2.3,
                order = 1,
            },

            blank1 = {
                type = "description",
                name = " ",
                width = 0.1,
                order = 1.5,
            },

            enabled = {
                type = "toggle",
                name = "Enable Situation",
                desc = "If this situation should be checked and activated",
                hidden = function() return not S end,
                get = function() return S.enabled end,
                set = function(_, newValue)
                        S.enabled = newValue
                        if newValue then
                            Options:SendMessage("DC_SITUATION_ENABLED")
                        else
                            Options:SendMessage("DC_SITUATION_DISABLED")
                        end
                    end,
                width = 0.7,
                order = 2,
            },



            situationSettings = CreateSettingsTab(1, true),

            situationActions = {

                type = "group",
                name = "Situation Actions",
                order = 2,

                args = {
                
                
                    transitionGroup = {

                        type = "group",
                        name = "View Transition",
                        order = 1,

                        args = {
                

                            zoomToggle = {
                                type = "toggle",
                                name = "Zoom",
                                desc = "Set a zoom level when this situation is activated",
                                get = function() return S.cameraActions.zoomSetting ~= "off" end,
                                set = function(_, newValue)
                                        if newValue then
                                            S.cameraActions.zoomSetting = "set"
                                        else
                                            S.cameraActions.zoomSetting = "off"
                                        end
                                    end,
                                order = 1,
                            },
                            
                            zoomSetting = {
                                type = "select",
                                name = "Zoom Setting",
                                desc = "How the camera should react to this situation with regards to zoom. Choose between:\n\nZoom In To: Zoom in to selected distance for this situation, will not zoom out.\n\nZoom Out To: Zoom out to selected distance for this situation, will not zoom in.\n\nZoom Range: Zoom in if past the maximum value, zoom out if past the minimum value.\n\nZoom Set To: Set the zoom to this value.",
                                get = function() return S.cameraActions.zoomSetting end,
                                set = function(_, newValue) S.cameraActions.zoomSetting = newValue end,
                                values = {["in"] = "Zoom In To", ["out"] = "Zoom Out To", ["set"] = "Zoom Set To", ["range"] = "Zoom Range"},
                                order = 1,
                            },
                            zoomValue = {
                                type = "range",
                                name = "Zoom Value",
                                desc = "The zoom value to set",
                                hidden = function() return S.cameraActions.zoomSetting == "range" end,
                                min = 0,
                                max = 39,
                                step = .5,
                                get = function() return S.cameraActions.zoomValue end,
                                set = function(_, newValue) S.cameraActions.zoomValue = newValue end,
                                order = 2,
                                width = "double",
                            },
                            zoomMin = {
                                type = "range",
                                name = "Zoom Min",
                                desc = "The min zoom value to set",
                                hidden = function() return S.cameraActions.zoomSetting ~= "range" end,
                                min = 0,
                                max = 39,
                                step = .5,
                                get = function() return S.cameraActions.zoomMin end,
                                set = function(_, newValue) S.cameraActions.zoomMin = newValue end,
                                order = 3,
                            },
                            zoomMax = {
                                type = "range",
                                name = "Zoom Max",
                                desc = "The max zoom value to set",
                                hidden = function() return S.cameraActions.zoomSetting ~= "range" end,
                                min = 0,
                                max = 39,
                                step = .5,
                                get = function() return S.cameraActions.zoomMax end,
                                set = function(_, newValue) S.cameraActions.zoomMax = newValue end,
                                order = 4,
                            },
                            
                            
                            transitionTime = {
                                type = "range",
                                name = "Time",
                                desc = "The time that it takes to transition to this situation",
                                min = .1,
                                max = 10,
                                softMax = 5,
                                step = .05,
                                get = function() return S.cameraActions.transitionTime end,
                                set = function(_, newValue) S.cameraActions.transitionTime = newValue end,
                                width = "double",
                                order = 2,
                            },
                            timeIsMax = {
                                type = "toggle",
                                name = "Don't Slow",
                                desc = "Camera shouldn't be slowed down to match the transition time. Thus, the transition takes at most the time given here but is otherwise as fast as the set Camera Move Speed allows.",
                                get = function() return S.cameraActions.timeIsMax end,
                                set = function(_, newValue) S.cameraActions.timeIsMax = newValue end,
                                order = 1,
                            },
                            
                            
                            
                            view = {
                                type = "toggle",
                                name = "Set View",
                                desc = "When this situation is activated (and only then), the selected view will be set",
                                get = function() return S.view.enabled end,
                                set = function(_, newValue) S.view.enabled = newValue end,
                                order = 3,
                            },
                            
                            viewSettings = {
                                type = "group",
                                name = "View Settings",
                                order = 30,
                                inline = true,
                                hidden = function() return not S.view.enabled end,
                                args = {
                                    view = {
                                        type = "select",
                                        name = "View",
                                        desc = "WoW allows you to store up to 5 custom camera views.\nView 1 is used by DynamicCam to save and restore views, so you cannot use this. Views 2 to 5 can be used by you. Simply bring the camera into the position you want to save and then enter into the console: \"/sv x\" (with x being the view number 2, 3, 4 or 5).",
                                        get = function() return S.view.viewNumber end,
                                        set = function(_, newValue) S.view.viewNumber = newValue end,
                                        values = {[2] = "2", [3] = "3", [4] = "4", [5] = "5"},
                                        order = 2,
                                        width = "half",
                                    },
                                    instant = {
                                        type = "toggle",
                                        name = "Instant",
                                        desc = "If the transition to this view should be instant",
                                        get = function() return S.view.instant end,
                                        set = function(_, newValue) S.view.instant = newValue end,
                                        order = 3,
                                        width = "half",
                                    },
                                    restoreView = {
                                        type = "toggle",
                                        name = "Restore",
                                        desc = "Restore view to what it was before the situation arose",
                                        get = function() return S.view.restoreView end,
                                        set = function(_, newValue) S.view.restoreView = newValue end,
                                        order = 5,
                                        width = "half",
                                    },
                                },

                            },
                            
                            
                            
                        },
                        
                    },


                    
                    
                    rotateSettings = {
                        type = "group",
                        name = "Rotation",
                        order = 4,

                        args = {
                        
                            rotateToggle = {
                                type = "toggle",
                                name = "Rotate (Pitch/Yaw)",
                                desc = "Start rotating the camera when this situation is activated (and stop when it's done)",
                                get = function() return S.cameraActions.rotate end,
                                set = function(_, newValue)
                                        S.cameraActions.rotate = newValue
                                        LibCamera:StopRotating()
                                    end,
                                order = 1,
                            },
                        
                            rotateSetting = {
                                type = "select",
                                name = "Rotate Setting",
                                desc = "How the camera should react to this situation with regards to rotating",
                                get = function() return S.cameraActions.rotateSetting end,
                                set = function(_, newValue) S.cameraActions.rotateSetting = newValue end,
                                values = {["continuous"] = "Continuously", ["degrees"] = "By Degrees",},
                                order = 1,
                            },
                            rotateSpeed = {
                                type = "range",
                                name = "Speed",
                                desc = "Speed at which to rotate, in degrees/second",
                                min = -900,
                                max = 900,
                                softMin = -90,
                                softMax = 90,
                                hidden = function() return S.cameraActions.rotateSetting ~= "continuous" end,
                                step = 1,
                                get = function() return S.cameraActions.rotateSpeed end,
                                set = function(_, newValue) S.cameraActions.rotateSpeed = newValue end,
                                order = 2,
                                width = "double",
                            },
                            yawDegrees = {
                                type = "range",
                                name = "Yaw (-Left/Right+)",
                                desc = "Number of degrees to yaw (left and right)",
                                min = -1400,
                                max = 1440,
                                softMin = -360,
                                softMax = 360,
                                hidden = function() return S.cameraActions.rotateSetting == "continuous" end,
                                step = 5,
                                get = function() return S.cameraActions.yawDegrees end,
                                set = function(_, newValue) S.cameraActions.yawDegrees = newValue end,
                                order = 2,
                            },
                            pitchDegrees = {
                                type = "range",
                                name = "Pitch (-Down/Up+)",
                                desc = "Number of degrees to pitch (up and down)",
                                min = -90,
                                max = 90,
                                -- hidden = function() return S.cameraActions.rotateSetting == "continuous" end,
                                step = 5,
                                get = function() return S.cameraActions.pitchDegrees end,
                                set = function(_, newValue) S.cameraActions.pitchDegrees = newValue end,
                                order = 3,
                            },
                            rotateBack = {
                                type = "toggle",
                                name = "Rotate Back",
                                desc = "When the situation ends, try to rotate back to the original position.",
                                get = function() return S.cameraActions.rotateBack end,
                                set = function(_, newValue) S.cameraActions.rotateBack = newValue end,
                                order = 4,
                            },
                        },
                    },

                    extraActions = {
                        type = "group",
                        name = "Fade UI",
                        order = 30,
                        args = {
                            fadeUI = {
                                type = "toggle",
                                name = "Fade UI",
                                desc = "Fades the UI to transDynamicCam during this situation.\n\nPressing escape will cancel the fade.",
                                get = function() return S.extras.hideUI end,
                                set = function(_, newValue) S.extras.hideUI = newValue end,
                                order = 1,
                            },
                            hideUIFadeOpacity = {
                                type = "range",
                                name = "Fade Opacity",
                                desc = "Fade the UI to this opacity.",
                                hidden = function() return not S.extras.hideUI end,
                                min = 0,
                                max = 1,
                                step = .01,
                                get = function() return S.extras.hideUIFadeOpacity end,
                                set = function(_, newValue) S.extras.hideUIFadeOpacity = newValue end,
                                order = 2,
                            },
                            actuallyHideUI = {
                                type = "toggle",
                                name = "Hide UI After Fade",
                                desc = "Actually hides the UI after the fade. Otherwise it is still interactable even when faded out.",
                                hidden = function() return not S.extras.hideUI or S.extras.hideUIFadeOpacity ~= 0 end,
                                get = function() return S.extras.actuallyHideUI end,
                                set = function(_, newValue) S.extras.actuallyHideUI = newValue end,
                                order = 3,
                            },
                            keepMinimap = {
                                type = "toggle",
                                name = "Keep Minimap",
                                desc = "Do not fade the minimap.",
                                hidden = function() return not S.extras.hideUI or S.extras.actuallyHideUI end,
                                get = function() return S.extras.keepMinimap end,
                                set = function(_, newValue) S.extras.keepMinimap = newValue end,
                                order = 4,
                            },
                        },
                    },



                },

            },



            situationTriggers = {

                type = "group",
                name = "Situation Triggers",
                order = 3,

                args = {
                
                
                    events = {
                        type = "input",
                        name = "Events",
                        desc = "",
                        get = function() return table.concat(S.events, ", ") end,
                        set = function(_, newValue)
                                if newValue == "" then
                                    S.events = {}
                                else
                                    newValue = string.gsub(newValue, "%s+", "")
                                    S.events = {strsplit(",", newValue)}
                                end
                                Options:SendMessage("DC_SITUATION_UPDATED", SID)
                            end,
                        width = "double",
                        order = 1,
                    },
                    
                    
                    
                    
                    eventsDefault = {
                        type = "execute",
                        name = "Restore default",
                        desc = "Your 'Events' deviate from the default. Click here to restore it.",
                        func = function() S.events = DynamicCam.defaults.profile.situations[SID].events end,
                        hidden = function()
                            if not DynamicCam.defaults.profile.situations[SID] then return true end
                            return EventsEqual(S.events, DynamicCam.defaults.profile.situations[SID].events)
                          end,
                        order = 3,
                    },
                    priority = {
                        type = "input",
                        name = "Priority",
                        desc = "If multiple situations are active at the same time, the one with the highest priority is chosen",
                        get = function() return ""..S.priority end,
                        set = function(_, newValue)
                                if tonumber(newValue) then
                                    S.priority = tonumber(newValue)
                                end
                                Options:SendMessage("DC_SITUATION_UPDATED", SID)
                            end,
                        width = "half",
                        order = 1,
                    },
                    delay = {
                        type = "input",
                        name = "Delay",
                        desc = "How long to delay exiting this situation",
                        get = function() return ""..S.delay end,
                        set = function(_, newValue)
                                if tonumber(newValue) then
                                    S.delay = tonumber(newValue)
                                end
                                Options:SendMessage("DC_SITUATION_UPDATED", SID)
                            end,
                        width = "half",
                        order = 2,
                    },
                    condition = {
                        type = "input",
                        name = "Condition",
                        desc = "When this situation should be activated.",
                        get = function() return S.condition end,
                        set = function(_, newValue)
                                S.condition = newValue
                                Options:SendMessage("DC_SITUATION_UPDATED", SID)
                            end,
                        multiline = 6,
                        width = "full",
                        order = 5,
                    },
                    conditionDefault = {
                        type = "execute",
                        name = "Restore default",
                        desc = "Your 'Condition' deviates from the default. Click here to restore it.",
                        func = function() S.condition = DynamicCam.defaults.profile.situations[SID].condition end,
                        hidden = function()
                            if not DynamicCam.defaults.profile.situations[SID] then return true end
                            return ScriptEqual(S.condition, DynamicCam.defaults.profile.situations[SID].condition)
                          end,
                        order = 6,
                    },
                    executeOnInit = {
                        type = "input",
                        name = "Initialization Script",
                        desc = "Called when the situation is loaded and when it is modified.",
                        get = function() return S.executeOnInit end,
                        set = function(_, newValue)
                                S.executeOnInit = newValue
                                Options:SendMessage("DC_SITUATION_UPDATED", SID)
                            end,
                        multiline = 6,
                        width = "full",
                        order = 10,
                    },
                    executeOnInitDefault = {
                        type = "execute",
                        name = "Restore default",
                        desc = "Your 'Initialization Script' deviates from the default. Click here to restore it.",
                        func = function() S.executeOnInit = DynamicCam.defaults.profile.situations[SID].executeOnInit end,
                        hidden = function()
                            if not DynamicCam.defaults.profile.situations[SID] then return true end
                            return ScriptEqual(S.executeOnInit, DynamicCam.defaults.profile.situations[SID].executeOnInit)
                          end,
                        order = 11,
                    },
                    executeOnEnter = {
                        type = "input",
                        name = "On Enter Script",
                        desc = "Called when the situation is selected as the active situation (before any thing else).",
                        get = function() return S.executeOnEnter end,
                        set = function(_, newValue) S.executeOnEnter = newValue end,
                        multiline = 6,
                        width = "full",
                        order = 20,
                    },
                    executeOnEnterDefault = {
                        type = "execute",
                        name = "Restore default",
                        desc = "Your 'On Enter Script' deviates from the default. Click here to restore it.",
                        func = function() S.executeOnEnter = DynamicCam.defaults.profile.situations[SID].executeOnEnter end,
                        hidden = function()
                            if not DynamicCam.defaults.profile.situations[SID] then return true end
                            return ScriptEqual(S.executeOnEnter, DynamicCam.defaults.profile.situations[SID].executeOnEnter)
                          end,
                        order = 21,
                    },
                    executeOnExit = {
                        type = "input",
                        name = "On Exit Script",
                        desc = "Called when the situation is overridden by another situation or the condition fails a check (before any thing else).",
                        get = function() return S.executeOnExit end,
                        set = function(_, newValue) S.executeOnExit = newValue end,
                        multiline = 6,
                        width = "full",
                        order = 30,
                    },
                    executeOnExitDefault = {
                        type = "execute",
                        name = "Restore default",
                        desc = "Your 'On Exit Script' deviates from the default. Click here to restore it.",
                        func = function() S.executeOnExit = DynamicCam.defaults.profile.situations[SID].executeOnExit end,
                        hidden = function()
                            if not DynamicCam.defaults.profile.situations[SID] then return true end
                            return ScriptEqual(S.executeOnExit, DynamicCam.defaults.profile.situations[SID].executeOnExit)
                          end,
                        order = 31,
                    },
                
                
                },
                
            },



            customImport = {

                type = "group",
                name = "Custom / Import",
                order = 4,

                args = {

                    newSituation = {
                        type = "execute",
                        name = "New Custom Situation",
                        desc = "Create a new custom situation.",
                        func = function() DynamicCam:PopupCreateCustomProfile() end,
                        order = 4,
                        width = "full",
                    },

                    copy = {
                        type = "execute",
                        name = "Copy",
                        desc = "Copy this situations settings so that you can paste it into another situation.\n\nDoesn't copy the condition or the advanced mode Lua scripts.",
                        hidden = function() return not S end,
                        func = function() copiedSituationID = SID end,
                        order = 5,
                        width = "half",
                    },

                    paste = {
                        type = "execute",
                        name = "Paste",
                        desc = "Paste the settings from that last copied situation.",
                        hidden = function() return not S end,
                        disabled = function() return not copiedSituationID end,
                        func = function()
                                DynamicCam:CopySituationInto(copiedSituationID, SID)
                                copiedSituationID = nil
                            end,
                        order = 6,
                        width = "half",
                    },

                    export = {
                        type = "execute",
                        name = "Export",
                        desc = "If you want to share the settings of this situation with others you can export it into a text string. Use the \"Import\" section of the DynamicCam settings to import strings you have received from others.",
                        hidden = function() return not S end,
                        func = function() DynamicCam:PopupExport(DynamicCam:ExportSituation(SID)) end,
                        order = 7,
                        width = "half",
                    },

                    deleteCustom = {
                        type = "execute",
                        name = "Delete",
                        desc = "Delete this custom situation",
                        hidden = function() return not S or not string.find(SID, "custom") end,
                        func = function() DynamicCam:DeleteCustomSituation(SID) end,
                        order = 8,
                        width = "half",
                    },

                },

            },

        },
    }
end


local profileSettings = {
    type = "group",
    name = "Profiles",
    order = 4,
    childGroups = "tab",
    args = {

        exportGroup = {
            type = "group",
            name = "Export currently active profile",
            order = 1000,
            args = {
                helpText = {
                    type = "description",
                    name = "If you want to share your profile with others you can export it into a text string. Use the \"Import\" section of the DynamicCam settings to import strings you have received from others.",
                    order = 0,
                },
                name = {
                    type = "input",
                    name = "Profile Name (Required!)",
                    desc = "The name that other people will see when importing this profile.",
                    get = function() return exportName end,
                    set = function(_, newValue) exportName = newValue end,
                    --width = "double",
                    order = 1,
                },
                author = {
                    type = "input",
                    name = "Author (Optional)",
                    desc = "A name that will be attached to the export so that other people know whom it's from.",
                    get = function() return exportAuthor end,
                    set = function(_, newValue) exportAuthor = newValue end,
                    order = 2,
                },
                export = {
                    type = "execute",
                    name = "Generate export string",
                    disabled = function() return not (exportName and exportName ~= "") end,
                    func = function() DynamicCam:PopupExport(DynamicCam:ExportProfile(exportName, exportAuthor)) end,
                    order = 3,
                },
            },
        },

        presetGroup = {
            type = "group",
            name = "Profile presets",
            order = 1010,
            args = {
                description = {
                    type = "description",
                    name = "Here are some preset profiles created by other DynamicCam users. Do you have a profile that's unlike any of these? Please export it and post it together with a name and description on the DynamicCam user forum! We will then consider putting it into the next release.",
                    order = 1,
                },
                loadPreset = {
                    type = "select",
                    name = "Load Preset",
                    desc = "Select a preset profile to load it.\n|cFFFF4040YOUR CURRENT PROFILE WILL BE OVERRIDDEN WITHOUT WARNING, SO MAKE A COPY IF YOU WANT TO KEEP IT!|r",
                    get = function() return "" end,
                    set = function(_, newValue) DynamicCam:LoadPreset(newValue) end,
                    values = function() return DynamicCam:GetPresets() end,
                    sorting = function() return DynamicCam:GetPresetsSorting() end,
                    width = "full",
                    order = 2,
                },
                presetDescriptions = {
                    type = "group",
                    name = "Descriptions",
                    order = 3,
                    inline = true,
                    args = {
                        description = {
                            type = "description",
                            name = function() return DynamicCam:GetPresetDescriptions() end,
                            order = 1,
                        },
                    },
                },
            },
        },
    },
}



local import = {
    type = "group",
    name = "Import",
    order = 5,
    args = {
        helpText = {
            type = "description",
            name = "If you have the DynamicCam import string for a profile or situation, paste it in the text box below to import it. You can generate such import strings yourself using the export functions in the \"Profiles\" or \"Situations\" sections of the DynamicCam settings.\n\n|cFFFF4040YOUR CURRENT PROFILE WILL BE OVERRIDDEN WITHOUT WARNING, SO MAKE A COPY IF YOU WANT TO KEEP IT!|r\n",
            order = 0,
        },
        import = {
            type = "input",
            name = "Paste and hit Accept to import!",
            desc = "Paste the DynamicCam import string of a profile or a situation.",
            get = function() return "" end,
            set = function(_, newValue) DynamicCam:Import(newValue) end,
            multiline = 10,
            width = "full",
            order = 20,
        },
    },
}








----------
-- CORE --
----------
function Options:OnInitialize()
    -- make sure to select something for the UI
    self:SelectSituation()

    -- register the gui with AceConfig and Blizz Options
    self:RegisterMenus()
end

function Options:OnEnable()
    -- register for dynamiccam messages
    self:RegisterMessage("DC_SITUATION_ACTIVE", "ReselectSituation")
    self:RegisterMessage("DC_SITUATION_INACTIVE", "ReselectSituation")
    self:RegisterMessage("DC_SITUATION_ENTERED", "ReselectSituation")
    self:RegisterMessage("DC_SITUATION_EXITED", "ReselectSituation")
end

function Options:OnDisable()
    self:UnregisterAllMessages()
end


---------
-- GUI --
---------
function Options:ClearSelection()
    SID = nil
    S = nil
end

-- This function is needed to call SelectSituation() and
-- ignore the "message" argument passed to ReselectSituation().
function Options:ReselectSituation()
    self:SelectSituation()
end

function Options:SelectSituation(selectMe)
    if selectMe and DynamicCam.db.profile.situations[selectMe] then
        S = DynamicCam.db.profile.situations[selectMe]
        SID = selectMe
    else
        if DynamicCam.currentSituationID then
            S = DynamicCam.db.profile.situations[DynamicCam.currentSituationID]
            SID = DynamicCam.currentSituationID
        else
            if not SID or not S then
                SID, S = next(DynamicCam.db.profile.situations)
            end
        end
    end

    LibStub("AceConfigRegistry-3.0"):NotifyChange("DynamicCam")
end



function Options:RegisterMenus()
    -- setup menu

    -- Add profile managing here, such that we can have export below it.
    profileSettings.args["settings"] = LibStub("AceDBOptions-3.0"):GetOptionsTable(DynamicCam.db)
    profileSettings.args["settings"]["name"] = "Manage profiles"

    local allOptions = {
        name = "DynamicCam",
        type = "group",
        childGroups = "tab",
        args = {
            generalTab = general,
            standardSettingsTab = CreateSettingsTab(2),
            situationSettingsTab = CreateSituationSettingsTab(3),
            profileSettingsTab = profileSettings,
            importTab = import,
        }
    }

    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("DynamicCam", allOptions)
    self.menu = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DynamicCam", "DynamicCam")

end






function DynamicCam:GetSituationList()
    local situationList = {}

    for id, situation in pairs(DynamicCam.db.profile.situations) do
        local prefix = ""
        local suffix = ""
        local customPrefix = ""

        if DynamicCam.currentSituationID == id then
            prefix = "|cFF00FF00"
            suffix = "|r"
        elseif not situation.enabled then
            prefix = "|cFF808A87"
            suffix = "|r"
        elseif self.conditionExecutionCache[id] then
            prefix = "|cFF63B8FF"
            suffix = "|r"
        end

        if string.find(id, "custom") then
            customPrefix = "Custom: "
        end

        situationList[id] = prefix..customPrefix..situation.name.." [Priority: "..situation.priority.."]"..suffix
    end

    return situationList
end









C_Timer.After(1, function()

    -- Disable the standard UI's mouse look slider.
    InterfaceOptionsMousePanelMouseLookSpeedSlider:Disable()
    InterfaceOptionsMousePanelMouseLookSpeedSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -10)
        GameTooltip:SetText("Overridden by \"Mouse Look\" settings\nof the addon DynamicCam!")
    end)
    InterfaceOptionsMousePanelMouseLookSpeedSlider:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)



    -- Prevent the user from activating MOTION_SICKNESS_CHARACTER_CENTERED.

    -- Automatically undo forbidden cvar changes.
    hooksecurefunc("SetCVar", function(cvar, value)
        if cvar == "CameraKeepCharacterCentered" and value == "1" then
            SetCVar("CameraKeepCharacterCentered", 0)
        end
    end)


    -- Hide the original motion sickness drop down.
    InterfaceOptionsAccessibilityPanelMotionSicknessDropdown:Hide()

    -- Replace it with my own copy, such that there will be no taint.
    local cameraKeepCharacterCentered = "CameraKeepCharacterCentered";
    local cameraReduceUnexpectedMovement = "CameraReduceUnexpectedMovement";
    local motionSicknessOptions = {
        {
            text = MOTION_SICKNESS_NONE,
            [cameraKeepCharacterCentered] = "0",
            [cameraReduceUnexpectedMovement] = "0"
        },
        {
            text = MOTION_SICKNESS_REDUCE_CAMERA_MOTION,
            [cameraKeepCharacterCentered] = "0",
            [cameraReduceUnexpectedMovement] = "1"
        },
        {
            text = "|cFFFF0000" .. MOTION_SICKNESS_CHARACTER_CENTERED .. " (disabled)|r",
            [cameraKeepCharacterCentered] = "1",
            [cameraReduceUnexpectedMovement] = "0"
        },
        {
            text = "|cFFFF0000" .. MOTION_SICKNESS_BOTH .. " (disabled)|r",
            [cameraKeepCharacterCentered] = "1",
            [cameraReduceUnexpectedMovement] = "1"
        },
    }
    local function GetMotionSicknessSelected()
        local SelectedcameraKeepCharacterCentered = GetCVar(cameraKeepCharacterCentered)
        local SelectedcameraReduceUnexpectedMovement = GetCVar(cameraReduceUnexpectedMovement)

        for option, cvars in pairs(motionSicknessOptions) do
            if ( cvars[cameraKeepCharacterCentered] == SelectedcameraKeepCharacterCentered and cvars[cameraReduceUnexpectedMovement] == SelectedcameraReduceUnexpectedMovement ) then
                return option;
            end
        end
    end


    local MyMotionSicknessDropdown = CreateFrame("Frame", "MyMotionSicknessDropdown", InterfaceOptionsAccessibilityPanel, "UIDropDownMenuTemplate")
    MyMotionSicknessDropdown:SetPoint("TOPLEFT", InterfaceOptionsAccessibilityPanelOverrideFadeOut, "BOTTOMLEFT", 90, -8)
    -- Use in place of dropDown:SetWidth.
    -- (Could not find where the original takes its width from, but 130 seems to be it.)
    UIDropDownMenu_SetWidth(MyMotionSicknessDropdown, 130)
    MyMotionSicknessDropdown.label = MyMotionSicknessDropdown:CreateFontString("MyMotionSicknessDropdownLabel", "BACKGROUND", "OptionsFontSmall")
    MyMotionSicknessDropdown.label:SetPoint("RIGHT", MyMotionSicknessDropdown, "LEFT")
    MyMotionSicknessDropdown.label:SetText(MOTION_SICKNESS_DROPDOWN)

    local function MyMotionSicknessDropdown_Initialize()

      local selectedValue = UIDropDownMenu_GetSelectedValue(MyMotionSicknessDropdown)

      local info = UIDropDownMenu_CreateInfo()

      -- Called when this option is selected.
      info.func = function(self)
          -- Try to set the cvars. They will be rectified by the cvar hook above.
          BlizzardOptionsPanel_SetCVarSafe(cameraKeepCharacterCentered, motionSicknessOptions[self.value][cameraKeepCharacterCentered])
          BlizzardOptionsPanel_SetCVarSafe(cameraReduceUnexpectedMovement, motionSicknessOptions[self.value][cameraReduceUnexpectedMovement])
          -- Then set the selected item accordingly.
          MyMotionSicknessDropdown.value = GetMotionSicknessSelected()
          UIDropDownMenu_SetSelectedValue(MyMotionSicknessDropdown, MyMotionSicknessDropdown.value)
        end

      for k, v in ipairs(motionSicknessOptions) do
          info.text = v.text
          info.value = k
          info.checked = k == selectedValue
          UIDropDownMenu_AddButton(info)
      end

    end


    UIDropDownMenu_Initialize(MyMotionSicknessDropdown, MyMotionSicknessDropdown_Initialize)
    MyMotionSicknessDropdown.value = GetMotionSicknessSelected()
    UIDropDownMenu_SetSelectedValue(MyMotionSicknessDropdown, MyMotionSicknessDropdown.value)


    -- Place a tooltip warning.
    MyMotionSicknessDropdown:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 10)
        GameTooltip:SetText("\"" .. MOTION_SICKNESS_CHARACTER_CENTERED .. "\" would disable many features of the\naddon DynamicCam and is therefore disabled.")
    end)
    MyMotionSicknessDropdown:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

end)






-- This is not working reliably. Especially the zoom when not set to default.
-- So we hide this for now.
-- defaultEasing = {
    -- type = "group",
    -- name = "Default Easing Functions",
    -- order = 2,
    -- inline = true,
    -- args = {
        -- easingZoom = {
            -- type = "select",
            -- name = "Zoom Easing",
            -- desc = "Which easing function to use for zoom.",
            -- get = function() return DynamicCam.db.profile.easingZoom end,
            -- set = function(_, newValue) DynamicCam.db.profile.easingZoom = newValue; end,
            -- values = easingValues,
            -- order = 1,
        -- },
        -- easingYaw = {
            -- type = "select",
            -- name = "Yaw Easing",
            -- desc = "Which easing function to use for yaw.",
            -- get = function() return DynamicCam.db.profile.easingYaw end,
            -- set = function(_, newValue) DynamicCam.db.profile.easingYaw = newValue end,
            -- values = easingValues,
            -- order = 2,
        -- },
        -- easingPitch = {
            -- type = "select",
            -- name = "Pitch Easing",
            -- desc = "Which easing function to use for pitch.",
            -- get = function() return DynamicCam.db.profile.easingPitch end,
            -- set = function(_, newValue) DynamicCam.db.profile.easingPitch = newValue end,
            -- values = easingValues,
            -- order = 3,
        -- },
    -- },
-- },



