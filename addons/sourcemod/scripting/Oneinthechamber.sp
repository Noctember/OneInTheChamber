#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <multicolors>

#pragma newdecls required

#define PLUGIN_TAG "{blue}[OITC]{default}"
#define POSITION_X  "POSITION_X"
#define POSITION_Y  "POSITION_Y"
#define POSITION_Z  "POSITION_Z"
#define COLLISION_PUSH 17
Handle ARRAY_Spawns;
bool PluginEnabled;

int NumberOfSpawns;
int Points[MAXPLAYERS+1];
bool Immunised[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "One in the chamber",
	author = "Noctember",
	description = "",
	version = "0.1",
	url = "https://steamcommunity.com/id/NCBRRR/"
};

public void OnPluginStart()
{	
	RegAdminCmd("sm_createspawn", Command_CreateSpawn, ADMFLAG_CONFIG, "Create a new spawn");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("switch_team", Event_JoinTeam);
	HookEvent("player_team", Event_JoinTeam);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
			SDKHook(i, SDKHook_PostThinkPost, OnPostThinkPost);
			SDKHook(i, SDKHook_WeaponDrop, Hook_WeaponDrop);
		}
	}
	
	ARRAY_Spawns = CreateArray();
}

public void OnMapStart()
{
	char mapName[45];
	GetCurrentMap(mapName, sizeof(mapName));
	PluginEnabled = LoadConfiguration(mapName);
	if (!PluginEnabled)
	{
		SetFailState("%s No spawn defined for this map", PLUGIN_TAG)
		ServerCommand("sm plugins unload Oneinthechamber");
	}
	else
	{
		ServerCommand("mp_freezetime 0");
		ServerCommand("mp_warmuptime 0");
		ServerCommand("mp_roundtime_defuse 0");
		ServerCommand("mp_do_warmup_period 0");
		ServerCommand("mp_roundtime_hostage 1");
		ServerCommand("mp_teammates_are_enemies 1");
		ServerCommand("mp_ignore_round_win_conditions 1");
	}
}

stock bool LoadConfiguration(const char[] mapName)
{
	char path[75];
	BuildPath(Path_SM, path, sizeof(path), "configs/oitc/%s.cfg", mapName);
	
	if (!DirExists("addons/sourcemod/configs/oitc"))
		CreateDirectory("/addons/sourcemod/configs/oitc", 777);
	
	Handle file = INVALID_HANDLE;
	if (!FileExists(path))
		file = OpenFile(path, "w");
	else
		file = OpenFile(path, "r");
	
	char line[200];
	ClearArray(ARRAY_Spawns);
	
	while (!IsEndOfFile(file) && ReadFileLine(file, line, sizeof(line)))
	{
		char positions[3][15];
		ExplodeString(line, ";", positions, sizeof positions, sizeof positions[]);
		
		Handle trie = CreateTrie();
		SetTrieValue(trie, POSITION_X, StringToFloat(positions[0]));
		SetTrieValue(trie, POSITION_Y, StringToFloat(positions[1]));
		SetTrieValue(trie, POSITION_Z, StringToFloat(positions[2]));
		
		PushArrayCell(ARRAY_Spawns, trie);
	}
	CloseHandle(file);
	
	NumberOfSpawns = GetArraySize(ARRAY_Spawns);
	
	return true;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_PostThinkPost, OnPostThinkPost);
	SDKHook(client, SDKHook_WeaponDrop, Hook_WeaponDrop);
	
	Points[client] = 0;

}

public Action Command_CreateSpawn(int client, int args)
{
	if (!PluginEnabled)
		return Plugin_Handled;
	
	if (client == 0)
	{
		PrintToServer("%s Try using this command in game.", PLUGIN_TAG);
		return Plugin_Handled;
	}
	
	float newSpawn[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", newSpawn);
	
	Handle trie = CreateTrie();
	SetTrieValue(trie, POSITION_X, newSpawn[0]);
	SetTrieValue(trie, POSITION_Y, newSpawn[1]);
	SetTrieValue(trie, POSITION_Z, newSpawn[2]);
	PushArrayCell(ARRAY_Spawns, trie);
	
	CPrintToChat(client, "%s New spawn added!", PLUGIN_TAG);
	
	NumberOfSpawns++;
	
	SaveConfiguration();
	
	return Plugin_Handled;
}
public void Event_JoinTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	CreateTimer(3.0, Timer_Respawn, client);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (!PluginEnabled || !IsValidClient(client))
		return;
	
	CreateTimer(0.5, CheckAmmo, client);
		
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	SetEntityRenderColor(client, 100, 255, 100, 200);
	
	Immunised[client] = true;
	
	CreateTimer(5.0, Timer_SetMortality, client);
	
	CPrintToChat(client, "%s You are immunised for 5 seconds!", PLUGIN_TAG);
	
	if(NumberOfSpawns == 0)
		return;
	
	int spawnID = GetRandomInt(0, NumberOfSpawns - 1);
	Handle positions = GetArrayCell(ARRAY_Spawns, spawnID);
	
	float newSpawn[3];
	GetTrieValue(positions, POSITION_X, newSpawn[0]);
	GetTrieValue(positions, POSITION_Y, newSpawn[1]);
	GetTrieValue(positions, POSITION_Z, newSpawn[2]);
	
	SetEntProp(client, Prop_Data, "m_CollisionGroup", COLLISION_PUSH);
	
	TeleportEntity(client, newSpawn, NULL_VECTOR, NULL_VECTOR);
}

public Action CheckAmmo(Handle timer, any client)
{
	if ((!IsValidClient(client) || !IsPlayerAlive(client)) || (GetClientTeam(client) == CS_TEAM_SPECTATOR))
	return;
	
	int c4 = GetPlayerWeaponSlot(client, CS_SLOT_C4);
	if (c4 != -1)
		RemovePlayerItem(client, c4);
	
	int secondary = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	if (secondary != -1)
		RemovePlayerItem(client, secondary);
	
	int primary = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
	if (primary != -1)
		RemovePlayerItem(client, primary);
	
	int nadeslot = GetPlayerWeaponSlot(client, CS_SLOT_GRENADE);
	if (nadeslot != -1)
		RemovePlayerItem(client, nadeslot);
	
	GivePlayerItem(client, "weapon_deagle");
	
	SetEntProp(GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY), Prop_Data, "m_iClip1", 0);
	SetEntProp(GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY), Prop_Send, "m_iPrimaryReserveAmmoCount", 0);
	SetEntProp(GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY), Prop_Send, "m_iSecondaryReserveAmmoCount", 0);
	
	SetAmmo(GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY));
}

stock void SetAmmo(int weapon)
{
	if (!IsValidEntity(weapon))
		return;
	
	int client = GetEntPropEnt(weapon, Prop_Data, "m_hOwner");
	
	if (client == -1)
		return;
		
	int ammo = GetEntProp(weapon, Prop_Data, "m_iClip1")+1;
	SetEntProp(weapon, Prop_Data, "m_iClip1", ammo);
	SetEntProp(weapon, Prop_Send, "m_iSecondaryReserveAmmoCount", 0);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
		Points[i] = 0;
}

public Action Timer_SetMortality(Handle timer, any client)
{
	if(IsValidClient(client))
	{
		SetEntityRenderMode(client, RENDER_TRANSCOLOR);
		SetEntityRenderColor(client);
		
		Immunised[client] = false;
	}
	
	return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int&attacker, int&inflictor, float&damage, int&damagetype, int&weapon, float damageForce[3], float damagePosition[3])
{
	if (!PluginEnabled)
		return Plugin_Continue;
		
	if (victim == attacker || attacker == 0)
		return Plugin_Continue;
	
	if (Immunised[victim])
		return Plugin_Handled;
	
	damage *= GetRandomFloat(100.0, 999.0);
	damageForce[0] *= GetRandomFloat(500.0, 800.0);
	damageForce[1] *= GetRandomFloat(500.0, 800.0);
	damageForce[2] *= GetRandomFloat(500.0, 800.0);
	
	if(weapon != -1)
	{
		char sWeapon[32];
		GetEntityClassname(weapon, sWeapon, sizeof(sWeapon));
		
		if(StrEqual(sWeapon, "weapon_knife"))
			Points[attacker]+= 2;
		else
			Points[attacker]+= 1;
			
		CS_SetClientContributionScore(attacker, Points[attacker]);
			
		SetAmmo(GetPlayerWeaponSlot(attacker, CS_SLOT_SECONDARY));
	}
	
	return Plugin_Changed;
}

public Action Hook_WeaponDrop(int client, int weapon)
{
    if(IsValidEdict(weapon))
        AcceptEntityInput(weapon, "Kill");        
    return Plugin_Continue;
} 

public Action Event_OnPlayerDeath(Handle event, char[] name, bool dontBroadcast)
{
	if (!PluginEnabled)
		return Plugin_Continue;
		
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	if(attacker == 0)
		return Plugin_Continue;
	
	CreateTimer(5.0, Timer_Respawn, victim);
	
	return Plugin_Continue;
}

public Action Timer_Refill(Handle timer, any client)
{
	int weapon = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	if(weapon != -1)
		SetAmmo(weapon);
	
	return Plugin_Continue;
}

public Action Timer_Respawn(Handle timer, any client)
{
	if(IsValidClient(client))
		CS_RespawnPlayer(client);	
	
	return Plugin_Continue;
}

public Action OnPostThinkPost(int entity)
{
	if (!PluginEnabled)
		return Plugin_Continue;
		
	SetEntProp(entity, Prop_Send, "m_bInBuyZone", 0);
	return Plugin_Continue;
}

stock void SaveConfiguration()
{
	char path[75], mapName[45];
	GetCurrentMap(mapName, sizeof(mapName));
	
	BuildPath(Path_SM, path, sizeof(path), "configs/oitc/%s.cfg", mapName);
	
	Handle file = OpenFile(path, "w");
	for (int i = 0; i < GetArraySize(ARRAY_Spawns); i++)
	{
		Handle trie = GetArrayCell(ARRAY_Spawns, i);
		float Px = 0.0;
		float Py = 0.0;
		float Pz = 0.0;
		GetTrieValue(trie, POSITION_X, Px);
		GetTrieValue(trie, POSITION_Y, Py);
		GetTrieValue(trie, POSITION_Z, Pz);
		WriteFileLine(file, "%f;%f;%f", Px, Py, Pz);
	}
	CloseHandle(file);
}

stock bool IsValidClient(int client)
{
	if (client <= 0)return false;
	if (client > MaxClients)return false;
	if (!IsClientConnected(client))return false;
	return IsClientInGame(client);
}