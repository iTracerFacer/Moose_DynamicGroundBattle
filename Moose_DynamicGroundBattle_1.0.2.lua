--[[
    Script: Moose_DynamicGroundBattle.lua
    Written by: [F99th-TracerFacer]
    Version: 1.0.2
    Date: 11 November 2024
    Updated: 12 November 2024
    Description: This script creates a dynamic ground battle between Red and Blue coalitions 
    along a series of zones which can be arranged in a line or any other configuration creating a dynamic ground battle.

    Capture Zone Behavior
        - Zone Capture states: Captured, Guarded, Empty, Attacked, Neutral
        - Zone Colors: Red, Blue, Green, Orange
            Red: Captured by Red
            Blue: Captured by Blue
            Orange: Contested
            Green: Empty 

    Spawning And Patrol Behavior:
        - Infantry and armor groups for both sides spawn at random locations in their own zones. 
        - Each group then calculates the shortest distance to the nearest enemy zone and moves to that zone to patrol. 
        - Every ASSIGN_TASKS_SCHED seconds, the script will check the ZONE_CAPTURE states of all zones and assign tasks to groups accordingly. 
        - Any group NOT moving, will recieve orders to patrol the nearest enemy zone. Any unit already moving will be left alone.
        - Any troops dropped off through CTLD in these zones will begin to obey these orders as well.
        - Spawn frequency calculated based on the number of alive warehouses.
        - Infantry can be disabled from moving patrols if desired.
        - In the event of DCS assigning a ridiculous path to an object, simply stop the object and it will be reassigned a new patrol path next round.

  Warehouse System & Spawn Frequencey Behavior:
    1. Warehouses:
        - Each side (Red and Blue) has a set of warehouses defined in the `redWarehouses` and `blueWarehouses` tables.
        - The number of warehouses can be adjusted by adding or removing entries from these tables and ensuring there is a matching object in the mission editor.        
    
    2. Spawn Frequency Calculation:
        - The function `CalculateSpawnFrequency` calculates the spawn frequency based on the number of alive warehouses.
        - The spawn frequency is a ratio of alive warehouses to total warehouses.
        - If all warehouses are alive, the spawn frequency is (100%) of the base setting.
        - If half of the warehouses are alive, the spawn frequency is (50%).
        - If no warehouses are alive, the spawn frequency is (0%) (no more spawns).
        - So for example, if you set your spawn frequency to 300 seconds, and only 50% of your warehouses are alive, the actual spawn frequency will be 600 seconds.
        - This dynamic adjustment ensures that the reinforcement rate is directly impacted by the number of operational warehouses.
    
    3. Mark points are automatically added to the map for each warehouse. 
        - Include the warehouse name and a list of nearby ground units within a specified radius.
        - Uppdated every `UPDATE_MARK_POINTS_SCHED` seconds.
        - The maximum distance to search for units near a warehouse is defined by the `MAX_WAREHOUSE_UNIT_LIST_DISTANCE` variable.
        - The mark points are displayed to all players on the map as a form of "intel" on the battlefield.
        - Can be disabled by setting `ENABLE_WAREHOUSE_MARKERS` to false.

    General Setup Requirements:
        - The script relies on the MOOSE framework for DCS World. Ensure that the MOOSE framework is installed and running on the mission.
        - Ensure that all groups and zones mentioned below are created in the mission editor. You can adjust the names of the groups and zones as needed or
        add more groups and zones to the script. Ensure that the names in this script match the names in the mission editor.


    Groups and Zones to be created in the editor (all LATE ACTIVATE): 
        - Red Infantry Groups: RedInfantry1, RedInfantry2, RedInfantry3, RedInfantry4, RedInfantry5, RedInfantry6
        - Red Armor Groups: RedArmor1, RedArmor2, RedArmor3, RedArmor4, RedArmor5, RedArmor6
        - Blue Infantry Groups: BlueInfantry1, BlueInfantry2, BlueInfantry3, BlueInfantry4, BlueInfantry5, BlueInfantry6
        - Blue Armor Groups: BlueArmor1, BlueArmor2, BlueArmor3, BlueArmor4, BlueArmor5

        - Red Zones: FrontLine1, FrontLine2, FrontLine3, FrontLine4, FrontLine5, FrontLine6
        - Blue Zones: FrontLine7, FrontLine8, FrontLine9, FrontLine10, FrontLine11, FrontLine12

        - Red Warehouses: RedWarehouse1-1, RedWarehouse2-1, RedWarehouse3-1, RedWarehouse4-1, RedWarehouse5-1, RedWarehouse6-1
        - Blue Warehouses: BlueWarehouse1-1, BlueWarehouse2-1, BlueWarehouse3-1, BlueWarehouse4-1, BlueWarehouse5-1, BlueWarehouse6-1
        - ** Note Warehouse names are based on the static "unit name" in the mission editor. **
 
--]]

--[[
  --If you don't have command centers setup in another file, uncommnent this section below:
  -- Create Command Centers and Missions for each side
  -- Must have a blue unit named "BLUEHQ" and a red unit named "REDHQ" in the mission editor. 

  --Build Command Center and Mission for Blue
  US_CC = COMMANDCENTER:New( GROUP:FindByName( "BLUEHQ" ), "USA HQ" )
  US_Mission = MISSION:New( US_CC, "Insurgent Sandstorm", "Primary", "Clear the front lines of enemy activity.", coalition.side.BLUE)    
  US_Score = SCORING:New( "Insurgent Sandstorm - Blue" )
  US_Mission:AddScoring( US_Score )
  US_Mission:Start()
  US_Score:SetMessagesHit(false)
  US_Score:SetMessagesDestroy(false)
  US_Score:SetMessagesScore(false)  
      
  --Build Command Center and Mission Red
  RU_CC = COMMANDCENTER:New( GROUP:FindByName( "REDHQ" ), "Russia HQ" )
  RU_Mission = MISSION:New (RU_CC, "Insurgent Sandstorm", "Primary", "Destroy U.S. and NATO forces.", coalition.side.RED)
  RU_Score = SCORING:New("Insurgent Sandstorm - Red")
  RU_Mission:AddScoring( RU_Score)
  RU_Mission:Start()
  RU_Score:SetMessagesHit(false)
  RU_Score:SetMessagesDestroy(false)
  RU_Score:SetMessagesScore(false)

]]

-- Infantry Patrol Settings
-- Due to some maps or locations where infantry moving is either not desired or has problems with the terrain you can disable infantry moving patrols. 
-- Set to false, infantry units will spawn, and never move from their spawn location. This could be considered a defensive position and probably a good idea.
local MOVING_INFANTRY_PATROLS = false
local ENABLE_WAREHOUSE_MARKERS = true -- Enable or disable the warehouse markers on the map.
local UPDATE_MARK_POINTS_SCHED = 60 -- Update the map markers for warehouses every 300 seconds. ENABLE_WAREHOUSE_MARKERS must be set to true for this to work.
local MAX_WAREHOUSE_UNIT_LIST_DISTANCE = 5000 -- Maximum distance to search for units near a warehouse to display on map markers. 

-- Control Spawn frequency and limits of ground units. 
local INIT_RED_INFANTRY = 5         -- Initial number of Red Infantry groups
local MAX_RED_INFANTRY = 100          -- Maximum number of Red Infantry groups
local SPAWN_SCHED_RED_INFANTRY = 1800 -- Spawn Red Infantry groups every 1800 seconds

local INIT_RED_ARMOR = 25           -- Initial number of Red Armor groups
local MAX_RED_ARMOR = 200            -- Maximum number of Red Armor groups
local SPAWN_SCHED_RED_ARMOR = 300  -- Spawn Red Armor groups every 300 seconds

local INIT_BLUE_INFANTRY = 5           -- Initial number of Blue Infantry groups
local MAX_BLUE_INFANTRY = 100            -- Maximum number of Blue Infantry groups
local SPAWN_SCHED_BLUE_INFANTRY = 1800   -- Spawn Blue Infantry groups every 1800 seconds

local INIT_BLUE_ARMOR = 25           -- Initial number of Blue Armor groups0
local MAX_BLUE_ARMOR = 200            -- Maximum number of Blue Armor groups
local SPAWN_SCHED_BLUE_ARMOR = 300  -- Spawn Blue Armor groups every 300 seconds

local ASSIGN_TASKS_SCHED = 600      -- Assign tasks to groups every 600 seconds. New groups added will wait this long before moving.




-- Define capture zones for each side with a visible radius.
-- These zones will be used to create capture zones for each side. The capture zones will be used to determine the state of each zone (captured, guarded, empty, attacked, neutral).
-- The zones will also be used to spawn ground units for each side.
-- The zones should be created in the mission editor and named accordingly.
-- You can add more zones as needed. The script will create capture zones for each zone and assign tasks to groups based on the zone states.
-- Maybe the zones are along a front line, or they follow a road, or they are scattered around the map. You can arrange the zones in any configuration you like. 

local redZones = {
    ZONE:New("FrontLine1"),
    ZONE:New("FrontLine2"),
    ZONE:New("FrontLine3"),
    ZONE:New("FrontLine4"),
    ZONE:New("FrontLine5"),
    ZONE:New("FrontLine6")
}

local blueZones = {
    ZONE:New("FrontLine7"),
    ZONE:New("FrontLine8"),
    ZONE:New("FrontLine9"),
    ZONE:New("FrontLine10"),
    ZONE:New("FrontLine11"),
    ZONE:New("FrontLine12")
}

-- Define warehouses for each side. These warehouses will be used to calculate the spawn frequency of ground units.
-- The warehouses should be created in the mission editor and named accordingly. 
local redWarehouses = {
    STATIC:FindByName("RedWarehouse1-1"), -- Static units key of off unit name in mission editor rather than just the name field. weird. =\ (hours wasted! ha!)
    STATIC:FindByName("RedWarehouse2-1"),
    STATIC:FindByName("RedWarehouse3-1"),
    STATIC:FindByName("RedWarehouse4-1"),
    STATIC:FindByName("RedWarehouse5-1"),
    STATIC:FindByName("RedWarehouse6-1")
}

local blueWarehouses = {
    STATIC:FindByName("BlueWarehouse1-1"),
    STATIC:FindByName("BlueWarehouse2-1"),
    STATIC:FindByName("BlueWarehouse3-1"),
    STATIC:FindByName("BlueWarehouse4-1"),
    STATIC:FindByName("BlueWarehouse5-1"),
    STATIC:FindByName("BlueWarehouse6-1")
}

-- Define templates for infantry and armor groups. These templates will be used to randomize the groups spawned in the zones.
-- The templates should be created in the mission editor and named accordingly.
-- You can add more templates as needed. The script will randomly select a template for each group spawned.
-- The more templates you make, the more variety you can add to the groups that are spawned. 
local redInfantryTemplates = {
    "RedInfantry1",
    "RedInfantry2",
    "RedInfantry3",
    "RedInfantry4",
    "RedInfantry5",
    "RedInfantry6"
}

local redArmorTemplates = {
    "RedArmor1",
    "RedArmor2",
    "RedArmor3",
    "RedArmor4",
    "RedArmor5",
    "RedArmor6",
    "RedArmor7",
    "RedArmor8",
    "RedArmor9",
    "RedArmor10"

}

local blueInfantryTemplates = {
    "BlueInfantry1",
    "BlueInfantry2",
    "BlueInfantry3",
    "BlueInfantry4",
    "BlueInfantry5",
    "BlueInfantry6"
}

local blueArmorTemplates = {
    "BlueArmor1",
    "BlueArmor2",
    "BlueArmor3",
    "BlueArmor4",
    "BlueArmor5"
}

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- DO NOT EDIT BELOW THIS LINE
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Adds mark points on the map for each warehouse in the provided list.
--- Each mark point includes the warehouse's name and a list of nearby ground units within a specified radius.

-- Function to add mark points on the map for each warehouse in the provided list
local function addMarkPoints(warehouses, coalition)
    for _, warehouse in ipairs(warehouses) do
        if warehouse then
            local warehousePos = warehouse:GetVec3()
            local details
            if coalition == 2 then
                if warehouse:GetCoalition() == 2 then
                    details = "Warehouse: " .. warehouse:GetName() .. "\nThis warehouse needs to be protected.\n"
                else
                    details = "Warehouse: " .. warehouse:GetName() .. "\nThis is a primary target as it is directly supplying enemy units.\n"
                end
            elseif coalition == 1 then
                if warehouse:GetCoalition() == 1 then
                    details = "Warehouse: " .. warehouse:GetName() .. "\nThis warehouse needs to be protected.\nNearby Units:\n"
                else
                    details = "Warehouse: " .. warehouse:GetName() .. "\nThis is a primary target as it is directly supplying enemy units.\n"
                end
            end

            local coordinate = COORDINATE:NewFromVec3(warehousePos)
            local marker = MARKER:New(coordinate, details):ToCoalition(coalition):ReadOnly()
            marker:Remove(UPDATE_MARK_POINTS_SCHED)
        else
            env.info("addMarkPoints: Warehouse not found or is nil")
        end
    end
end

local function updateMarkPoints()
    addMarkPoints(redWarehouses, 2) -- Blue coalition sees red warehouses as targets
    addMarkPoints(blueWarehouses, 2) -- Blue coalition sees blue warehouses as needing protection
    addMarkPoints(redWarehouses, 1) -- Red coalition sees red warehouses as needing protection
    addMarkPoints(blueWarehouses, 1) -- Red coalition sees blue warehouses as targets
end

-- If enabled, update the mark points for the warehouses every UPDATE_MARK_POINTS_SCHED seconds.
if ENABLE_WAREHOUSE_MARKERS then
    SCHEDULER:New(nil, updateMarkPoints, {}, 10, UPDATE_MARK_POINTS_SCHED)
end

-- Table to keep track of zones and their statuses
local zoneStatuses = {}

-- Function to create a capture zone
local function CreateCaptureZone(zone, coalition)
    local captureZone = ZONE_CAPTURE_COALITION:New(zone, coalition)
    if captureZone then
        local coordinate = captureZone:GetCoordinate()
        if coordinate then
            env.info("Created capture zone at coordinates: " .. coordinate:ToStringLLDMS())
            captureZone:Start(5, 30) -- Check every 5 seconds, capture after 30 seconds
        else
            env.error("Failed to get coordinates for zone: " .. zone:GetName() .. " Did you add the group to the editor?")
        end
    else
        env.error("Failed to create capture zone for zone: " .. zone:GetName() .. " Did you add the group to the editor?")
    end
    return captureZone
end

-- Custom OnEnterCaptured method
--- @param Functional.Protect#ZONE_CAPTURE_COALITION self
function ZONE_CAPTURE_COALITION:OnEnterCaptured(From, Event, To)
    if From ~= To then
        local Coalition = self:GetCoalition()
        self:E({ Coalition = Coalition })
        local zoneName = self:GetZoneName()
        zoneStatuses[zoneName] = { zone = self, coalition = Coalition }
        if Coalition == coalition.side.BLUE then
            self:Smoke(SMOKECOLOR.Blue)
            self:UndrawZone()
            self:DrawZone(-1, {0, 0, 1}, 2) -- Draw the zone on the map for 30 seconds, blue color, and thickness 2
            US_CC:MessageTypeToCoalition(string.format("%s has been captured by the USA", self:GetZoneName()), MESSAGE.Type.Information)
            RU_CC:MessageTypeToCoalition(string.format("%s has been captured by the USA", self:GetZoneName()), MESSAGE.Type.Information)
        else
            self:Smoke(SMOKECOLOR.Red)
            self:UndrawZone()
            self:DrawZone(-1, {1, 0, 0}, 2) -- Draw the zone on the map for 30 seconds, red color, and thickness 2
            RU_CC:MessageTypeToCoalition(string.format("%s has been captured by Russia", self:GetZoneName()), MESSAGE.Type.Information)
            US_CC:MessageTypeToCoalition(string.format("%s has been captured by Russia", self:GetZoneName()), MESSAGE.Type.Information)
        end
    end
end

-- Custom OnEnterGuarded method
--- @param Functional.ZoneCaptureCoalition#ZONE_CAPTURE_COALITION self
function ZONE_CAPTURE_COALITION:OnEnterGuarded(From, Event, To)
    if From ~= To then
        local Coalition = self:GetCoalition()
        self:E({ Coalition = Coalition })
        local zoneName = self:GetZoneName()
        zoneStatuses[zoneName] = { zone = self, coalition = Coalition }
        if Coalition == coalition.side.BLUE then
            self:Smoke(SMOKECOLOR.Blue)
            -- Draw zone DARK BLUE for guarded
            self:UndrawZone()
            self:DrawZone(-1, {0, 0, 0.5}, 2) -- Draw the zone on the map for 30 seconds, dark blue color, and thickness 2
            US_CC:MessageTypeToCoalition(string.format("%s is under protection of the USA", self:GetZoneName()), MESSAGE.Type.Information)
            RU_CC:MessageTypeToCoalition(string.format("%s is under protection of the USA", self:GetZoneName()), MESSAGE.Type.Information)
        else
            self:Smoke(SMOKECOLOR.Red)
            -- Draw zone DARK RED for guarded
            self:UndrawZone()
            self:DrawZone(-1, {0.5, 0, 0}, 2) -- Draw the zone on the map for 30 seconds, dark red color, and thickness 2
            RU_CC:MessageTypeToCoalition(string.format("%s is under protection of Russia", self:GetZoneName()), MESSAGE.Type.Information)
            US_CC:MessageTypeToCoalition(string.format("%s is under protection of Russia", self:GetZoneName()), MESSAGE.Type.Information)
        end
    end
end

-- Custom OnEnterEmpty method
--- @param Functional.Protect#ZONE_CAPTURE_COALITION self
function ZONE_CAPTURE_COALITION:OnEnterEmpty(From, Event, To)
    if From ~= To then
        self:E({ Coalition = "None" })
        local zoneName = self:GetZoneName()
        zoneStatuses[zoneName] = { zone = self, coalition = "None" }
        self:Smoke(SMOKECOLOR.Green)
        self:UndrawZone()
        self:DrawZone(-1, {0, 1, 0}, 2) -- Draw the zone on the map for 30 seconds, green color, and thickness 2
        US_CC:MessageTypeToCoalition(string.format("%s is now empty", self:GetZoneName()), MESSAGE.Type.Information)
        RU_CC:MessageTypeToCoalition(string.format("%s is now empty", self:GetZoneName()), MESSAGE.Type.Information)
    end
end

-- Custom OnEnterAttacked method
--- @param Functional.Protect#ZONE_CAPTURE_COALITION self
function ZONE_CAPTURE_COALITION:OnEnterAttacked(From, Event, To)
    if From ~= To then
        local Coalition = self:GetCoalition()
        self:E({ Coalition = Coalition })
        local zoneName = self:GetZoneName()
        zoneStatuses[zoneName] = { zone = self, coalition = Coalition }
        if Coalition == coalition.side.BLUE then
            self:Smoke(SMOKECOLOR.Blue)
            -- Draw the zone orange for contested
            self:UndrawZone()
            self:DrawZone(-1, {1, 0.5, 0}, 2) -- Draw the zone on the map for 30 seconds, orange color, and thickness 2
            US_CC:MessageTypeToCoalition(string.format("%s is under attack by Russia", self:GetZoneName()), MESSAGE.Type.Information)
            RU_CC:MessageTypeToCoalition(string.format("%s is attacking the USA", self:GetZoneName()), MESSAGE.Type.Information)
        else
            self:Smoke(SMOKECOLOR.Red)
            self:UndrawZone()
            self:DrawZone(-1, {1, 0.5, 0}, 2) -- Draw the zone on the map for 30 seconds, orange color, and thickness 2
            RU_CC:MessageTypeToCoalition(string.format("%s is under attack by the USA", self:GetZoneName()), MESSAGE.Type.Information)
            US_CC:MessageTypeToCoalition(string.format("%s is attacking Russia", self:GetZoneName()), MESSAGE.Type.Information)
        end
    end
end

-- Custom OnEnterNeutral method
--- @param Functional.Protect#ZONE_CAPTURE_COALITION self
function ZONE_CAPTURE_COALITION:OnEnterNeutral(From, Event, To)
    if From ~= To then
        self:E({ Coalition = "Neutral" })
        local zoneName = self:GetZoneName()
        zoneStatuses[zoneName] = { zone = self, coalition = "Neutral" }
        self:Smoke(SMOKECOLOR.Green)
        self:UndrawZone()
        self:DrawZone(-1, {0, 1, 0}, 2) -- Draw the zone on the map for 30 seconds, green color, and thickness 2
        US_CC:MessageTypeToCoalition(string.format("%s is now neutral", self:GetZoneName()), MESSAGE.Type.Information)
        RU_CC:MessageTypeToCoalition(string.format("%s is now neutral", self:GetZoneName()), MESSAGE.Type.Information)
    end
end

-- Create capture zones for Red and Blue
local redCaptureZones = {}
local blueCaptureZones = {}

-- Iterate over all red zones to create capture zones
for _, zone in ipairs(redZones) do
    -- Attempt to create a capture zone for the current red zone
    local captureZone = CreateCaptureZone(zone, coalition.side.RED)
    if captureZone then
        -- If successful, add the capture zone to the redCaptureZones table
        table.insert(redCaptureZones, captureZone)
        -- Log the creation of the capture zone
        env.info("Created Red capture zone: " .. zone:GetName())
        -- Draw the zone on the map with infinite duration, red color, and thickness 2
        zone:DrawZone(30, {1, 0, 0}, 2)
        -- Initialize the zone status
        zoneStatuses[zone:GetName()] = { zone = captureZone, coalition = coalition.side.RED }
    else
        -- If creation fails, log an error message
        env.error("Failed to create Red capture zone: " .. zone:GetName())
    end
end

-- Iterate over all blue zones to create capture zones
for _, zone in ipairs(blueZones) do
    -- Attempt to create a capture zone for the current blue zone
    local captureZone = CreateCaptureZone(zone, coalition.side.BLUE)
    if captureZone then
        -- If successful, add the capture zone to the blueCaptureZones table
        table.insert(blueCaptureZones, captureZone)
        -- Log the creation of the capture zone
        env.info("Created Blue capture zone: " .. zone:GetName())
        -- Draw the zone on the map with infinite duration, blue color, and thickness 2
        zone:DrawZone(30, {0, 0, 1}, 2)
        -- Initialize the zone status
        zoneStatuses[zone:GetName()] = { zone = captureZone, coalition = coalition.side.BLUE }
    else
        -- If creation fails, log an error message
        env.error("Failed to create Blue capture zone: " .. zone:GetName())
    end
end

-- Function to handle zone capture
local function OnZoneCaptured(event)
    local zone = event.zone
    local coalition = event.coalition

    if zone and coalition then
        env.info("OnZoneCaptured: Zone " .. zone:GetName() .. " captured by coalition " .. coalition)

        -- Update the zone state
        if coalition == coalition.side.RED then
            zoneStates[zone:GetName()] = "RED"
            zone:SetCoalition(coalition.side.RED)
        elseif coalition == coalition.side.BLUE then
            zoneStates[zone:GetName()] = "BLUE"
            zone:SetCoalition(coalition.side.BLUE)
        else
            zoneStates[zone:GetName()] = "NEUTRAL"
            zone:SetCoalition(coalition.side.NEUTRAL)
        end
    else
        env.error("OnZoneCaptured: Invalid zone or coalition")
    end
end

-- Function to handle zone guarded events
local function OnZoneGuarded(event)
    local zone = event.Zone
    local coalition = event.Coalition

    if coalition == coalition.side.RED then
        env.info("Red is guarding zone: " .. zone:GetName())
    elseif coalition == coalition.side.BLUE then
        env.info("Blue is guarding zone: " .. zone:GetName())
    end
end

-- Function to handle zone empty events
local function OnZoneEmpty(event)
    local zone = event.Zone
    env.info("Zone is empty: " .. zone:GetName())
end

-- Function to handle zone attacked events
local function OnZoneAttacked(event)
    local zone = event.Zone
    local attackingGroups = zone:GetGroups()
    local makeup = {}

    for _, group in ipairs(attackingGroups) do
        local groupName = group:GetName()
        local unitTypes = {}

        for _, unit in ipairs(group:GetUnits()) do
            local unitType = unit:GetTypeName()
            unitTypes[unitType] = (unitTypes[unitType] or 0) + 1
        end

        table.insert(makeup, {groupName = groupName, unitTypes = unitTypes})
    end

    local makeupMessage = ""
    for _, groupInfo in ipairs(makeup) do
        makeupMessage = makeupMessage .. "Group: " .. groupInfo.groupName .. "\n"
        for unitType, count in pairs(groupInfo.unitTypes) do
            makeupMessage = makeupMessage .. "  " .. unitType .. ": " .. count .. "\n"
        end
    end

    local messageText = "Zone is being attacked: " .. zone:GetName() .. "\n" .. makeupMessage
    env.info(messageText)

    -- Announce to the player
    MESSAGE:New(messageText, 15):ToAll()
end

-- Function to handle zone neutral events
local function OnZoneNeutral(event)
    local zone = event.Zone
    env.info("Zone is neutral: " .. zone:GetName())
end

-- Function to check the ZONE_CAPTURE states of all zones
local function CheckZoneStates()
    env.info("Checking zone states...")

    local zoneStates = {}

    local function processZones(zones, zoneType)
        env.info("Processing " .. zoneType)
        env.info("Number of zones: " .. #zones)
   
        local allGroups = SET_GROUP:New():FilterActive():FilterStart()

        for _, zone in ipairs(zones) do
            if zone then
                env.info("processZones: Zone object is valid")
                -- Check if the zone is of the correct type
                if zone.ClassName == "ZONE_CAPTURE_COALITION" then
                    env.info("processZones: Zone is of type ZONE_CAPTURE_COALITION")
                    local coalition = zone:GetCoalition()
                    env.info("processZones: Zone coalition: " .. tostring(coalition))
                    if coalition == 1 then
                        zoneStates[zone:GetZoneName()] = "RED"
                         env.info("processZones: Zone: " .. (zone:GetZoneName() or "nil") .. " State: RED")
                    elseif coalition == 2 then
                        zoneStates[zone:GetZoneName()] = "BLUE"
                         env.info("processZones: Zone: " .. (zone:GetZoneName() or "nil") .. " State: BLUE")
                    else
                        zoneStates[zone:GetZoneName()] = "NEUTRAL"
                        env.info("processZones: Zone: " .. (zone:GetZoneName() or "nil") .. " State: NEUTRAL")
                    end

                    local groupsInZone = {}
                    allGroups:ForEachGroup(function(group)
                        if group then
                            env.info("processZones: Checking group: " .. group:GetName())
                            if group.IsCompletelyInZone then
                                if group:IsCompletelyInZone(zone) then
                                    table.insert(groupsInZone, group)
                                end
                            else
                                env.error("processZones: IsCompletelyInZone method not found in group: " .. group:GetName())
                                -- Log available methods on the group object
                                for k, v in pairs(group) do
                                    env.info("processZones: Group method: " .. tostring(k) .. " = " .. tostring(v))
                                end
                            end
                        else
                            env.error("processZones: Invalid group")
                        end
                    end)

                    env.info("processZones: Number of groups in zone: " .. #groupsInZone)
                else
                    env.error("processZones: Zone is not of type ZONE_CAPTURE_COALITION")
                    -- Log available methods on the zone object
                    for k, v in pairs(zone) do
                        env.info("processZones: Zone method: " .. tostring(k) .. " = " .. tostring(v))
                    end
                end
                if not zone.GetZoneName then
                    env.error("processZones: Missing GetZoneName method in " .. zoneType)
                end
            else
                env.error("processZones: Invalid zone in " .. zoneType)
            end
        end
    
    end

    processZones(redCaptureZones, "redZones")
    processZones(blueCaptureZones, "blueZones")

    -- Log the zoneStates table
    for zoneName, state in pairs(zoneStates) do
        env.info("CheckZoneStates: Zone: " .. zoneName .. " State: " .. state)
    end

    return zoneStates
end

-- Function to assign tasks to groups
local function AssignTasks(group, zoneStates)
    if not group or not group.GetCoalition or not group.GetCoordinate or not group.GetVelocity then
        env.info("AssignTasks: Invalid group or missing methods")
        return
    end

    local velocity = group:GetVelocityVec3()
    local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
    if speed > 0 then
        env.info("AssignTasks: Group " .. group:GetName() .. " is already moving. No new orders sent.")
        return
    end

    env.info("Assigning tasks to group: " .. group:GetName())
    local groupCoalition = group:GetCoalition()
    local groupCoordinate = group:GetCoordinate()
    local closestZone = nil
    local closestDistance = math.huge

    env.info("Group Coalition: " .. tostring(groupCoalition))
    env.info("Group Coordinate: " .. groupCoordinate:ToStringLLDMS())

    for zoneName, state in pairs(zoneStates) do
        env.info("Checking Zone: " .. zoneName .. " with state: " .. tostring(state))
        
        -- Convert state to a number for comparison
        local stateCoalition = (state == "RED" and 1) or (state == "BLUE" and 2) or nil
        
        if stateCoalition and stateCoalition ~= groupCoalition then
            local zone = ZONE:FindByName(zoneName)
            if zone then
                local zoneCoordinate = zone:GetCoordinate()
                local distance = groupCoordinate:Get2DDistance(zoneCoordinate)
                --env.info("Zone Coordinate: " .. zoneCoordinate:ToStringLLDMS())
                --env.info("Distance to zone " .. zoneName .. ": " .. distance)
                if distance < closestDistance then
                    closestDistance = distance
                    closestZone = zone
                    env.info("New closest zone: " .. zoneName .. " with distance: " .. distance)
                end
            else
                env.info("AssignTasks: Zone not found - " .. zoneName)
            end
        else
            env.info("Zone " .. zoneName .. " is already controlled by coalition: " .. tostring(state))
        end
    end

    if closestZone then
        env.info(group:GetName() .. " is moving to and patrolling zone " .. closestZone:GetName())
        --MESSAGE:New(group:GetName() .. " is moving to and patrolling zone " .. closestZone:GetName(), 10):ToAll()

        -- Create a patrol task using the GROUP:PatrolZones method
        local patrolZones = {closestZone}
        local speed = 20 -- Example speed, adjust as needed
        local formation = "Cone" -- Example formation, adjust as needed
        local delayMin = 30 -- Example minimum delay, adjust as needed
        local delayMax = 60 -- Example maximum delay, adjust as needed

        group:PatrolZones(patrolZones, speed, formation, delayMin, delayMax)
    else
        env.info("AssignTasks: No suitable zone found for group " .. group:GetName())
    end
end


-- Function to check if a group contains infantry units
local function IsInfantryGroup(group)
    env.info("IsInfantryGroup: Checking group: " .. group:GetName())
    for _, unit in ipairs(group:GetUnits()) do
        local unitTypeName = unit:GetTypeName()
        env.info("IsInfantryGroup: Checking unit: " .. unit:GetName() .. " with type: " .. unitTypeName)
        if unitTypeName:find("Infantry") or unitTypeName:find("Soldier") or unitTypeName:find("Paratrooper") then
            env.info("IsInfantryGroup: Found infantry unit in group: " .. group:GetName())
            return true
        end
    end
    return false
end

-- Function to assign tasks to groups
local function AssignTasksToGroups()
    env.info("AssignTasksToGroups: Starting task assignments")
    local zoneStates = CheckZoneStates()
    local allGroups = SET_GROUP:New():FilterActive():FilterStart()

    local function processZone(zone, zoneColor)
        if zone then
            env.info("AssignTasksToGroups: Processing " .. zoneColor .. " zone: " .. zone:GetName())
            local groupsInZone = {}
            allGroups:ForEachGroup(function(group)
                if group then
                    if group.IsCompletelyInZone then
                        if group:IsCompletelyInZone(zone) then
                            table.insert(groupsInZone, group)
                        end
                    else
                        env.error("AssignTasksToGroups: IsCompletelyInZone method not found in group: " .. group:GetName())
                        for k, v in pairs(group) do
                            env.info("AssignTasksToGroups: Group method: " .. tostring(k) .. " = " .. tostring(v))
                        end
                    end
                else
                    env.error("AssignTasksToGroups: Invalid group")
                end
            end)
            env.info("AssignTasksToGroups: Found " .. #groupsInZone .. " groups in " .. zoneColor .. " zone: " .. zone:GetName())
            for _, group in ipairs(groupsInZone) do
                if IsInfantryGroup(group) == true then
                    if MOVING_INFANTRY_PATROLS == true then
                        env.info("AssignTasksToGroups: Assigning tasks to infantry group: " .. group:GetName())
                        AssignTasks(group, zoneStates)
                    else
                        env.info("AssignTasksToGroups: Skipping infantry group: " .. group:GetName())
                    end
                else
                    env.info("AssignTasksToGroups: Assigning tasks to group: " .. group:GetName())
                    AssignTasks(group, zoneStates)
                end
            end
        else
            env.info("AssignTasksToGroups: Invalid " .. zoneColor .. " zone")
        end
    end

    for _, zone in ipairs(redZones) do
        processZone(zone, "red")
    end

    for _, zone in ipairs(blueZones) do
        processZone(zone, "blue")
    end

    env.info("AssignTasksToGroups: Task assignments completed. Running again in " .. ASSIGN_TASKS_SCHED .. " seconds.")
end


-- Function to calculate spawn frequency in seconds
local function CalculateSpawnFrequency(warehouses, baseFrequency)
    local totalWarehouses = #warehouses
    local aliveWarehouses = 0

    for _, warehouse in ipairs(warehouses) do
        local life = warehouse:GetLife()
        if life and life > 0 then
            aliveWarehouses = aliveWarehouses + 1
        end
    end

    if totalWarehouses == 0 or aliveWarehouses == 0 then
        return math.huge -- Stop spawning if there are no warehouses or no alive warehouses
    end

    local frequency = baseFrequency * (totalWarehouses / aliveWarehouses)
    
    return frequency
end

-- Function to calculate spawn frequency percentage
local function CalculateSpawnFrequencyPercentage(warehouses)
    local totalWarehouses = #warehouses
    local aliveWarehouses = 0

    for _, warehouse in ipairs(warehouses) do
        local life = warehouse:GetLife()
        if life and life > 0 then
            aliveWarehouses = aliveWarehouses + 1
        end
    end

    if totalWarehouses == 0 then
        return 0 -- Avoid division by zero
    end

    local percentage = (aliveWarehouses / totalWarehouses) * 100
    return percentage
end

-- Add event handlers for zone capture
for _, captureZone in ipairs(redCaptureZones) do
    captureZone:OnEnterCaptured(OnZoneCaptured)
    captureZone:OnEnterGuarded(captureZone.OnEnterGuarded)
    captureZone:OnEnterEmpty(OnZoneEmpty)
    captureZone:OnEnterAttacked(OnZoneAttacked)
    captureZone:OnEnterNeutral(OnZoneNeutral)
end

for _, captureZone in ipairs(blueCaptureZones) do
    captureZone:OnEnterCaptured(OnZoneCaptured)
    captureZone:OnEnterGuarded(captureZone.OnEnterGuarded)
    captureZone:OnEnterEmpty(OnZoneEmpty)
    captureZone:OnEnterAttacked(OnZoneAttacked)
    captureZone:OnEnterNeutral(OnZoneNeutral)
end

-- Calculate spawn frequencies
local redInfantrySpawnFrequency = CalculateSpawnFrequency(redWarehouses, SPAWN_SCHED_RED_INFANTRY)
local redArmorSpawnFrequency = CalculateSpawnFrequency(redWarehouses, SPAWN_SCHED_RED_ARMOR)
local blueInfantrySpawnFrequency = CalculateSpawnFrequency(blueWarehouses, SPAWN_SCHED_BLUE_INFANTRY)
local blueArmorSpawnFrequency = CalculateSpawnFrequency(blueWarehouses, SPAWN_SCHED_BLUE_ARMOR)

-- Calculate spawn frequency percentages
local redSpawnFrequencyPercentage = CalculateSpawnFrequencyPercentage(redWarehouses, coalition.side.RED)
local blueSpawnFrequencyPercentage = CalculateSpawnFrequencyPercentage(blueWarehouses, coalition.side.BLUE)

-- Display spawn frequency percentages to the user
MESSAGE:New("Red side spawn frequency: " .. redSpawnFrequencyPercentage .. "%", 30):ToRed()
MESSAGE:New("Blue side spawn frequency: " .. blueSpawnFrequencyPercentage .. "%", 30):ToBlue()

-- Schedule ground spawns using the calculated frequencies
redInfantrySpawn = SPAWN:New("RedInfantryGroup")
    :InitRandomizeTemplate(redInfantryTemplates)
    :InitRandomizeZones(redZones)
    :InitLimit(INIT_RED_INFANTRY, MAX_RED_INFANTRY)
    :SpawnScheduled(redInfantrySpawnFrequency, 0.5)

redArmorSpawn = SPAWN:New("RedArmorGroup")
    :InitRandomizeTemplate(redArmorTemplates)
    :InitRandomizeZones(redZones)
    :InitLimit(INIT_RED_ARMOR, MAX_RED_ARMOR)
    :SpawnScheduled(redArmorSpawnFrequency, 0.5)

blueInfantrySpawn = SPAWN:New("BlueInfantryGroup")
    :InitRandomizeTemplate(blueInfantryTemplates)
    :InitRandomizeZones(blueZones)
    :InitLimit(INIT_BLUE_INFANTRY, MAX_BLUE_INFANTRY)
    :SpawnScheduled(blueInfantrySpawnFrequency, 0.5)

blueArmorSpawn = SPAWN:New("BlueArmorGroup")
    :InitRandomizeTemplate(blueArmorTemplates)
    :InitRandomizeZones(blueZones)
    :InitLimit(INIT_BLUE_ARMOR, MAX_BLUE_ARMOR)
    :SpawnScheduled(blueArmorSpawnFrequency, 0.5)

env.info("Dynamic Ground Battle & Zone capture initialized.")


-- Function to monitor and announce warehouse status
local function MonitorWarehouses()
    local blueWarehousesAlive = 0
    local redWarehousesAlive = 0

    for _, warehouse in ipairs(blueWarehouses) do
        if warehouse:IsAlive() then
            blueWarehousesAlive = blueWarehousesAlive + 1
        end
    end

    for _, warehouse in ipairs(redWarehouses) do
        if warehouse:IsAlive() then
            redWarehousesAlive = redWarehousesAlive + 1
        end
    end

    -- Debug messages to check values
    env.info("MonitorWarehouses: blueWarehousesAlive = " .. blueWarehousesAlive)
    env.info("MonitorWarehouses: redWarehousesAlive = " .. redWarehousesAlive)

    -- Calculate spawn frequencies
    local redInfantrySpawnFrequency = CalculateSpawnFrequency(redWarehouses, SPAWN_SCHED_RED_INFANTRY)
    local redArmorSpawnFrequency = CalculateSpawnFrequency(redWarehouses, SPAWN_SCHED_RED_ARMOR)
    local blueInfantrySpawnFrequency = CalculateSpawnFrequency(blueWarehouses, SPAWN_SCHED_BLUE_INFANTRY)
    local blueArmorSpawnFrequency = CalculateSpawnFrequency(blueWarehouses, SPAWN_SCHED_BLUE_ARMOR)

    -- Calculate spawn frequency percentages
    local redSpawnFrequencyPercentage = CalculateSpawnFrequencyPercentage(redWarehouses)
    local blueSpawnFrequencyPercentage = CalculateSpawnFrequencyPercentage(blueWarehouses)

    -- Log the values
    env.info("MonitorWarehouses: redInfantrySpawnFrequency = " .. redInfantrySpawnFrequency)
    env.info("MonitorWarehouses: redArmorSpawnFrequency = " .. redArmorSpawnFrequency)
    env.info("MonitorWarehouses: blueInfantrySpawnFrequency = " .. blueInfantrySpawnFrequency)
    env.info("MonitorWarehouses: blueArmorSpawnFrequency = " .. blueArmorSpawnFrequency)
    env.info("MonitorWarehouses: redSpawnFrequencyPercentage = " .. redSpawnFrequencyPercentage)
    env.info("MonitorWarehouses: blueSpawnFrequencyPercentage = " .. blueSpawnFrequencyPercentage)

    local msg = "[Warehouse status:]\n"
    msg = msg .. "Red warehouses alive: " .. redWarehousesAlive .. " Reinforcements Capacity: " .. redSpawnFrequencyPercentage .. "%" .. "\n"
    msg = msg .. "Blue warehouses alive: " .. blueWarehousesAlive .. " Reinforcements Capacity: " .. blueSpawnFrequencyPercentage .. "%" .. "\n"
    MESSAGE:New(msg, 30):ToAll()


end

-- Function to check the wincondition. If either side owns all zones, mission ends.
local function checkWinCondition()
    local blueOwned = true
    local redOwned = true
  
    for zoneName, owner in pairs(zoneStatuses) do
      if owner ~= 1 then
        redOwned = false
      end
      if owner ~= 2 then
        blueOwned = false
      end
    end
  
    if blueOwned then
      MESSAGE:New("Blue side wins! They own all the capture zones.", 60):ToAll()
      SOUND:New("UsaTheme.ogg"):ToAll()
      return true
    elseif redOwned then
      MESSAGE:New("Red side wins! They own all the capture zones.", 60):ToAll()
      SOUND:New("MotherRussia.ogg"):ToAll()
      return true
    end
  
    return false
  end
  
  -- Timer function to periodically check the win condition
  local function monitorWinCondition()
    if not checkWinCondition() then
      -- Schedule the next check in 60 seconds
      TIMER:New(monitorWinCondition):Start(60)
    end
  end
  
  -- Start monitoring the win condition
  monitorWinCondition()

-- Scheduler to monitor warehouses every 120 seconds
SCHEDULER:New(nil, MonitorWarehouses, {}, 0, 120)

-- Scheduler to assign tasks to groups periodically
SCHEDULER:New(nil, AssignTasksToGroups, {}, 0, ASSIGN_TASKS_SCHED)  -- Check every 600 seconds (10 minutes) - Adjust as needed

-- Create a mission menu
local missionMenu = MENU_MISSION:New("Warehouse Monitoring")

-- Add a menu item to run the MonitorWarehouses function
MENU_MISSION_COMMAND:New("Check Warehouse Status", missionMenu, MonitorWarehouses)
