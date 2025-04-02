#pragma semicolon 1
#include <sourcemod>
#include <vip_core>
#include <utilshelper>
#include <multicolors>

#undef REQUIRE_PLUGIN
#tryinclude <ccc>
#tryinclude <sourcebanspp>
#define REQUIRE_PLUGIN

#define VIP_FEATURE_FLAGS "SetSMFlags"
#define DEBUG_PREFIX "[VIP-Flags]"

ConVar g_cvDebug;
bool g_bClientLoaded[MAXPLAYERS + 1];
bool g_bSbppClientsLoaded;
bool g_bReloadVips;
bool g_bLibraryCCC;
int g_iVIPFlags[MAXPLAYERS + 1];

public Plugin myinfo = 
{
    name = "[VIP] Sourcemod Flags", 
    author = "R1KO & inGame & maxime1907, +SyntX", 
    description = "Sets sourcemod flags from VIP features", 
    version = "3.2.5"
};

public void OnPluginStart()
{
    g_cvDebug = CreateConVar("sm_vipflags_debug", "1", "Enable debug messages", 0, true, 0.0, true, 1.0);
    AutoExecConfig(true);
    
    RegAdminCmd("sm_reloadvips", Command_ReloadVips, ADMFLAG_BAN);
    
    if (VIP_IsVIPLoaded())
    {
        VIP_OnVIPLoaded();
    }
}

public void OnAllPluginsLoaded()
{
    if (LibraryExists("ccc"))
        g_bLibraryCCC = true;
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "ccc", false))
        g_bLibraryCCC = true;
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "ccc", false))
        g_bLibraryCCC = false;
}

public Action Command_ReloadVips(int client, int args)
{
    ReloadVIPs();
    DebugPrint("%N reloaded VIP flags", client);
    CReplyToCommand(client, "%s Reloaded VIP flags for all players", DEBUG_PREFIX);
    return Plugin_Handled;
}

public void OnPluginEnd()
{
    if (CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "VIP_UnregisterFeature") == FeatureStatus_Available)
    {
        VIP_UnregisterFeature(VIP_FEATURE_FLAGS);
    }
}

public void VIP_OnVIPLoaded()
{
    VIP_RegisterFeature(VIP_FEATURE_FLAGS, STRING, _);
    DebugPrint("Feature registered: %s", VIP_FEATURE_FLAGS);
}

public void OnRebuildAdminCache(AdminCachePart part)
{
    if (part != AdminCache_Admins)
        return;

    if (g_bSbppClientsLoaded)
    {
        g_bSbppClientsLoaded = false;
        g_bReloadVips = true;
    }
}

#if defined _sourcebanspp_included
public bool SBPP_OnClientPreAdminCheck(AdminCachePart part)
{
    if (part == AdminCache_Admins)
        g_bSbppClientsLoaded = true;

    for (int client = 1; client <= MaxClients; client++)
        CheckLoadAdmin(client);

    if (part == AdminCache_Admins)
    {
        if (g_bReloadVips)
            ReloadVIPs();
        g_bReloadVips = false;
    }

    return false;
}
#endif

public void VIP_OnVIPClientLoaded(int client)
{
    if (VIP_IsClientVIP(client))
    {
        LoadVIPClient(client);
        ProcessClientFlags(client);
    }
}

public void VIP_OnVIPClientRemoved(int client, const char[] reason, int admin)
{
    RemoveVIPFlags(client);
    UnloadVIPClient(client);
}

void LoadVIPClient(int client)
{
    if (!client || !IsClientInGame(client))
        return;

#if defined _ccc_included
    if (g_bLibraryCCC && GetFeatureStatus(FeatureType_Native, "CCC_LoadClient") == FeatureStatus_Available)
        CCC_LoadClient(client);
#endif

    g_bClientLoaded[client] = true;
    CheckLoadAdmin(client);
}

void UnloadVIPClient(int client)
{
    if (!IsClientInGame(client))
        return;

#if defined _ccc_included
    if (g_bLibraryCCC && GetFeatureStatus(FeatureType_Native, "CCC_UnLoadClient") == FeatureStatus_Available)
        CCC_UnLoadClient(client);
#endif

    ServerCommand("sm_reloadadmins");
}

void ProcessClientFlags(int client)
{
    if (!IsClientInGame(client) || !VIP_IsClientVIP(client))
        return;

    // Store original flags before applying VIP flags
    int originalFlags = GetUserFlagBits(client);
    
    if (VIP_IsClientFeatureUse(client, VIP_FEATURE_FLAGS))
    {
        char sFlags[32];
        if (VIP_GetClientFeatureString(client, VIP_FEATURE_FLAGS, sFlags, sizeof(sFlags)) && sFlags[0] != '\0')
        {
            DebugPrint("%N - Raw flags: '%s'", client, sFlags);
            
            // Normalize to lowercase
            for (int i = 0; i < strlen(sFlags); i++)
                sFlags[i] = CharToLower(sFlags[i]);

            int flagBits = ReadFlagString(sFlags);
            if (flagBits != -1)
            {
                // Store VIP-granted flags
                g_iVIPFlags[client] = flagBits;
                
                // Apply flags: originalFlags | VIPFlags
                SetUserFlagBits(client, originalFlags | flagBits);
                DebugPrint("%N - Set flags: %d (%s) | Total: %d (%s)", 
                    client, 
                    flagBits, 
                    SMFlagBitsToString(flagBits),
                    GetUserFlagBits(client),
                    SMFlagBitsToString(GetUserFlagBits(client)));
            }
            else
            {
                DebugPrint("%N - Invalid flag string: '%s'", client, sFlags);
            }
        }
    }
}

void RemoveVIPFlags(int client)
{
    if (!IsClientInGame(client))
        return;

    // Remove only VIP-granted flags using bitwise AND with inverse
    int newFlags = GetUserFlagBits(client) & (~g_iVIPFlags[client]);
    SetUserFlagBits(client, newFlags);
    
    DebugPrint("%N - Removed VIP flags: %d (%s) | Remaining: %d (%s)", 
        client, 
        g_iVIPFlags[client], 
        SMFlagBitsToString(g_iVIPFlags[client]),
        newFlags,
        SMFlagBitsToString(newFlags));
        
    g_iVIPFlags[client] = 0;
    ServerCommand("sm_reloadadmins");
}

stock void CheckLoadAdmin(int client)
{
    if (IsClientInGame(client) && IsClientAuthorized(client))
    {
        RunAdminCacheChecks(client);

        if (g_bSbppClientsLoaded && g_bClientLoaded[client])
            NotifyPostAdminCheck(client);
    }
}

stock void ReloadVIPs()
{
    DebugPrint("Reloading VIPs for all players");
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            if (VIP_IsClientVIP(i))
            {
                LoadVIPClient(i);
                ProcessClientFlags(i);
            }
            else
            {
                RemoveVIPFlags(i);
            }
        }
    }
}

stock char[] SMFlagBitsToString(int flags)
{
    char buffer[32];
    buffer[0] = '\0';
    
    for (int i = 0; i < 26; i++)
    {
        if (flags & (1 << i))
        {
            Format(buffer, sizeof(buffer), "%s%c", buffer, 'a' + i);
        }
    }
    
    if (buffer[0] == '\0')
    {
        StrCat(buffer, sizeof(buffer), "none");
    }
    
    return buffer;
}

stock void DebugPrint(const char[] format, any ...)
{
    if (!g_cvDebug.BoolValue)
        return;
    
    char buffer[256];
    VFormat(buffer, sizeof(buffer), format, 2);
    
    LogMessage("%s %s", DEBUG_PREFIX, buffer);
    PrintToServer("%s %s", DEBUG_PREFIX, buffer);
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && CheckCommandAccess(i, "sm_admin", ADMFLAG_ROOT))
        {
            PrintToConsole(i, "%s %s", DEBUG_PREFIX, buffer);
        }
    }
}
