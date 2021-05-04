/* [ Includes ] */
#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <clientprefs>
#include <emitsoundany>

/* [ Compiler Options ] */
#pragma newdecls required
#pragma semicolon 1

/* [ Defines ] */
#define LoopClients(%1)			for(int %1 = 1; %1 < MaxClients; %1++) if(IsValidClient(%1))
#define Table_Main				"pMvpMusic"
#define AUTH_MAX_LENGTH			26

/* [ Database ] */
Database g_dbDatabase;

/* [ ArrayLists ] */
ArrayList g_arSounds[4];
ArrayList g_arRandom[3];

/* [ Enums ] */
enum struct Enum_PlayerInfo {
	char sAuthId[26];
	int iSound;
	float fVolume;
	bool bEnabled;
	bool bIsDataLoaded;
	bool bSaveData;
	
	void Reset() {
		this.sAuthId = "";
		this.iSound = -1;
		this.fVolume = 1.0;
		this.bIsDataLoaded = false;
		this.bSaveData = false;
		this.bEnabled = true;
	}
}
Enum_PlayerInfo g_eInfo[MAXPLAYERS + 1];

/* [ Integers ] */
int g_iCvar;

/* [ Chars ] */
static const char g_sSQL_CreateTable[] = "CREATE TABLE IF NOT EXISTS `"...Table_Main..."` (`SteamId` VARCHAR(32) NOT NULL, `Sound` INT NOT NULL DEFAULT '-1', `Volume` FLOAT NOT NULL DEFAULT '1.0',\
	`Enable` INT DEFAULT '1' NOT NULL, UNIQUE KEY `SteamID` (`SteamId`)) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_polish_ci;";
static const char g_sSQL_LoadData[] = "SELECT * FROM `"...Table_Main..."` WHERE `SteamId`='%s';";
static const char g_sSQL_InsertData[] = "INSERT INTO `"...Table_Main..."` (`SteamId`) VALUES ('%s');";
static const char g_sSQL_UpdateData[] = "UPDATE `"...Table_Main..."` SET `Sound`='%d', `Volume`='%.2f', `Enable`='%d' WHERE `SteamId`='%s';";

/* [ Menus ] */
Menu g_mMenu;

/* [ Chars ] */
char g_sChatTag[64], g_sMenuTag[64];

/* [ Plugin Author and Informations ] */
public Plugin myinfo =  {
	name = "[CS:GO] Pawel - [ Mvp Music ]", 
	author = "Pawel", 
	description = "Własna muzyka Mvp dla każdego gracza.", 
	version = "1.3.0", 
	url = "https://steamcommunity.com/id/pawelsteam"
};

/* [ Plugin Startup ] */
public void OnPluginStart() {
	/* [ Client Commands ] */
	RegConsoleCmd("sm_mvp", Mvp_Command, "Menu główne.");
	RegConsoleCmd("sm_music", Mvp_Command, "Menu główne.");
	RegConsoleCmd("sm_muzyka", Mvp_Command, "Menu główne.");
	RegConsoleCmd("sm_kit", Mvp_Command, "Menu główne.");
	RegConsoleCmd("sm_kits", Mvp_Command, "Menu główne.");
	
	/* [ Events ] */
	HookEvent("round_mvp", Event_RoundMvp);
	
	/* [ Database Connect ] */
	if (SQL_CheckConfig("Pawel_Mvp"))
		Database.Connect(SQL_Connect_Handler, "Pawel_Mvp");
	else
		SetFailState("[ ✘ Mvp Music » Core ✘ ] Brak konfiguracji \"Pawel_Mvp\" w databases.cfg .");
	
	/* [ ArrayLists ] */
	CreateArrays();
	
	/* [ LateLoad ] */
	LoopClients(i)
	OnClientPostAdminCheck(i);
}

/* [ Standard Actions ] */
public void OnMapStart() {
	if (SQL_CheckConfig("Pawel_Mvp"))
		Database.Connect(SQL_Connect_Handler, "Pawel_Mvp");
	else
		SetFailState("[ ✘ Mvp Music » Core ✘ ] Brak konfiguracji \"Pawel_Mvp\" w databases.cfg .");
	LoadConfig();
}

public void OnClientPostAdminCheck(int iClient) {
	if (IsValidClient(iClient)) {
		g_eInfo[iClient].Reset();
		SQL_PrepareLoadData(iClient);
	}
}

public void OnClientDisconnect(int iClient) {
	if (IsValidClient(iClient))
		g_eInfo[iClient].Reset();
}

public void OnMapEnd() {
	LoopClients(i)
	OnClientDisconnect(i);
	ClearArrays();
}

/* [ Commands ] */
public Action Mvp_Command(int iClient, int iArgs) {
	DisplayMvpMenu(iClient).Display(iClient, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

Menu DisplayMvpMenu(int iClient) {
	char sBuffer[512], sName[128];
	Format(sBuffer, sizeof(sBuffer), "[ ★ %s » Piosenki MVP ★ ]\n ", g_sMenuTag);
	Format(sBuffer, sizeof(sBuffer), "%s\n➪ Witaj, %N!", sBuffer, iClient);
	if (g_eInfo[iClient].iSound != -1) {
		g_arSounds[1].GetString(g_eInfo[iClient].iSound, sName, sizeof(sName));
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Aktualna piosenka: %s", sBuffer, sName);
	}
	Format(sBuffer, sizeof(sBuffer), "%s\n---------------------------------", sBuffer);
	g_mMenu = new Menu(Mvp_Handler);
	g_mMenu.SetTitle(sBuffer);
	g_mMenu.AddItem("", "» Wybierz piosenkę");
	g_mMenu.AddItem("", "» Ustaw głośność");
	Format(sBuffer, sizeof(sBuffer), "» %s piosenki MVP\n ", g_eInfo[iClient].bEnabled ? "Wyłącz":"Włącz");
	g_mMenu.AddItem("", sBuffer);
	return g_mMenu;
}

public int Mvp_Handler(Menu mMenu, MenuAction maAction, int iClient, int iPosition) {
	switch (maAction) {
		case MenuAction_Select: {
			switch (iPosition) {
				case 0, 1:DisplayMvpOption(iClient, iPosition).Display(iClient, MENU_TIME_FOREVER);
				case 2: {
					g_eInfo[iClient].bEnabled = g_eInfo[iClient].bEnabled ? false:true;
					g_eInfo[iClient].bSaveData = true;
					SQL_Update(iClient);
					CPrintToChat(iClient, "%s Piosenki MVP zostały %s{default}.", g_sChatTag, g_eInfo[iClient].bEnabled ? "{lime}włączone":"{lightred}wyłączone");
					DisplayMvpMenu(iClient).Display(iClient, MENU_TIME_FOREVER);
				}
			}
		}
		case MenuAction_End:delete mMenu;
	}
}

Menu DisplayMvpOption(int iClient, int iType) {
	char sBuffer[512], sName[128], sFlags[16], sItem[32];
	Format(sBuffer, sizeof(sBuffer), "[ ★ %s » Piosenki MVP ★ ]\n ", g_sMenuTag);
	switch (iType) {
		case 0: {
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Wybierz interesujący Cię utwór.", sBuffer);
			Format(sBuffer, sizeof(sBuffer), "%s\n---------------------------------", sBuffer);
			g_mMenu = new Menu(MvpList_Handler);
			g_mMenu.SetTitle(sBuffer);
			if (g_eInfo[iClient].iSound != -1)
				g_mMenu.AddItem("-1", "» Brak");
			for (int i = 0; i < g_arSounds[0].Length; i++) {
				g_arSounds[1].GetString(i, sName, sizeof(sName));
				g_arSounds[3].GetString(i, sFlags, sizeof(sFlags));
				Format(sBuffer, sizeof(sBuffer), "» %s", sName);
				IntToString(i, sItem, sizeof(sItem));
				g_mMenu.AddItem(sItem, sBuffer, CheckDrawType(iClient, sFlags, i));
			}
			if (!g_mMenu.ItemCount)
				g_mMenu.AddItem("", "» Właściciel serwera nie dodał żadnej piosenki :c\n ", ITEMDRAW_DISABLED);
			g_mMenu.ExitBackButton = true;
		}
		case 1: {
			Format(sBuffer, sizeof(sBuffer), "[ ★ %s » Piosenki MVP ★ ]\n ", g_sMenuTag);
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Głośność: %.2f", sBuffer, g_eInfo[iClient].fVolume);
			Format(sBuffer, sizeof(sBuffer), "%s\n---------------------------------", sBuffer);
			g_mMenu = new Menu(MvpVolume_Handler);
			g_mMenu.SetTitle(sBuffer);
			g_mMenu.AddItem("0.05", "» +0.05");
			g_mMenu.AddItem("0.1", "» +0.1");
			g_mMenu.AddItem("0.05", "» -0.05");
			g_mMenu.AddItem("0.1", "» -0.1");
			g_mMenu.AddItem("0.0", "» Wycisz\n ");
			g_mMenu.ExitBackButton = true;
		}
	}
	return g_mMenu;
}

public int MvpList_Handler(Menu mMenu, MenuAction maAction, int iClient, int iPosition) {
	switch (maAction) {
		case MenuAction_Select: {
			char sItem[32], sName[128];
			mMenu.GetItem(iPosition, sItem, sizeof(sItem));
			int iSoundId = StringToInt(sItem);
			if (iSoundId != -1) {
				g_arSounds[1].GetString(iSoundId, sName, sizeof(sName));
				CPrintToChat(iClient, "%s Piosenka {lime}%s{default} została ustawiona.", g_sChatTag, sName);
			}
			g_eInfo[iClient].iSound = iSoundId;
			g_eInfo[iClient].bSaveData = true;
			SQL_Update(iClient);
			DisplayMvpOption(iClient, 0).Display(iClient, MENU_TIME_FOREVER);
		}
		case MenuAction_Cancel: {
			if (iPosition == MenuCancel_ExitBack)
				Mvp_Command(iClient, 0);
		}
		case MenuAction_End:delete mMenu;
	}
}

public int MvpVolume_Handler(Menu mMenu, MenuAction maAction, int iClient, int iPosition) {
	switch (maAction) {
		case MenuAction_Select: {
			char sItem[32];
			mMenu.GetItem(iPosition, sItem, sizeof(sItem));
			float fValue = StringToFloat(sItem);
			switch (iPosition) {
				case 0, 1: {
					g_eInfo[iClient].fVolume += fValue;
					if (g_eInfo[iClient].fVolume > 1.0)
						g_eInfo[iClient].fVolume = 1.0;
				}
				case 2, 3: {
					g_eInfo[iClient].fVolume -= fValue;
					if (g_eInfo[iClient].fVolume < 0.0)
						g_eInfo[iClient].fVolume = 0.0;
				}
				case 4:g_eInfo[iClient].fVolume = 0.0;
			}
			g_eInfo[iClient].bSaveData = true;
			SQL_Update(iClient);
			DisplayMvpOption(iClient, 1).Display(iClient, MENU_TIME_FOREVER);
		}
		case MenuAction_Cancel: {
			if (iPosition == MenuCancel_ExitBack)
				Mvp_Command(iClient, 0);
		}
		case MenuAction_End:delete mMenu;
	}
}

/* [ Events ] */
public Action Event_RoundMvp(Event eEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));
	if (!IsValidClient(iClient))return Plugin_Continue;
	
	if (g_eInfo[iClient].iSound == -1 && g_iCvar)
		GetRandomSound();
	else if (g_eInfo[iClient].iSound > -1) {
		char sSound[128], sPath[PLATFORM_MAX_PATH];
		g_arSounds[1].GetString(g_eInfo[iClient].iSound, sSound, sizeof(sSound));
		g_arSounds[2].GetString(g_eInfo[iClient].iSound, sPath, sizeof(sPath));
		PrecacheSoundAny(sPath);
		LoopClients(i) {
			if (g_eInfo[i].bEnabled && g_eInfo[i].fVolume) {
				ClientCommand(i, "playgamesound Music.StopAllMusic");
				CPrintToChat(i, "%s Aktualnie leci piosenka {lime}%s{default}, która należy do {lime}%N{default}.", g_sChatTag, sSound, iClient);
				EmitSoundToClientAny(i, sPath, -2, 0, 0, 0, g_eInfo[i].fVolume, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
			}
		}
	}
	return Plugin_Continue;
}

/* [ Database Connect ] */
public void SQL_Connect_Handler(Database dbDatabase, const char[] sError, any aData) {
	if (g_dbDatabase != null)
		return;
	if (dbDatabase == null)
		SetFailState("[ ✘ Mvp Music » Database ✘ ] Bład podczas połączenia z bazą: %s", sError);
	
	dbDatabase.SetCharset("utf8mb4");
	dbDatabase.Query(SQL_Init_Handler, g_sSQL_CreateTable, 0, DBPrio_High);
	g_dbDatabase = dbDatabase;
}

public void SQL_Init_Handler(Database dbDatabase, DBResultSet rs, const char[] sError, any aData) {
	if (rs == null)
		SetFailState("[ ✘ Mvp Music » Database ✘ ] Nie udało się utworzyć tabeli \""...Table_Main..."\": %s", sError);
}

void SQL_PrepareLoadData(int iClient) {
	if (!IsValidClient(iClient))return;
	
	if (g_dbDatabase == null) {
		LogError("[ ✘ Mvp Music » Database ✘ ] Wystąpił problem podczas wszytywania danych gracza...");
		return;
	}
	char sQuery[256];
	GetClientAuthId(iClient, AuthId_Steam2, g_eInfo[iClient].sAuthId, AUTH_MAX_LENGTH);
	Format(sQuery, sizeof(sQuery), g_sSQL_LoadData, g_eInfo[iClient].sAuthId);
	g_dbDatabase.Query(SQL_LoadData_Handler, sQuery, iClient);
}

public void SQL_LoadData_Handler(Database dbDatabase, DBResultSet rs, const char[] sError, int iClient) {
	if (dbDatabase == null || rs == null) {
		LogError("[ ✘ Mvp Music » Database ✘ ] Błąd podczas wczytywania danych z tabeli \""...Table_Main..."\":: %s", sError);
		return;
	}
	
	if (rs.RowCount && rs.FetchRow()) {
		g_eInfo[iClient].iSound = rs.FetchInt(1);
		g_eInfo[iClient].fVolume = rs.FetchFloat(2);
		g_eInfo[iClient].bEnabled = view_as<bool>(rs.FetchInt(3));
		g_eInfo[iClient].bIsDataLoaded = true;
	}
	else
		SQL_InsertData(iClient);
}

void SQL_InsertData(int iClient) {
	if (g_dbDatabase == null || !IsValidClient(iClient) || g_eInfo[iClient].bIsDataLoaded)
		return;
	
	char sQuery[256];
	Format(sQuery, sizeof(sQuery), g_sSQL_InsertData, g_eInfo[iClient].sAuthId);
	g_dbDatabase.Query(SQL_MvpMusic_Handler, sQuery, iClient);
}

void SQL_Update(int iClient) {
	if (g_dbDatabase == null || !IsValidClient(iClient) || !g_eInfo[iClient].bIsDataLoaded || !g_eInfo[iClient].bSaveData)
		return;
	g_eInfo[iClient].bSaveData = false;
	char sQuery[512];
	Format(sQuery, sizeof(sQuery), g_sSQL_UpdateData, g_eInfo[iClient].iSound, g_eInfo[iClient].fVolume, view_as<int>(g_eInfo[iClient].bEnabled), g_eInfo[iClient].sAuthId);
	g_dbDatabase.Query(SQL_MvpMusic_Handler, sQuery, iClient);
}

public void SQL_MvpMusic_Handler(Database dbDatabase, DBResultSet rs, const char[] sError, int iClient) {
	if (dbDatabase == null || rs == null) {
		LogError("[ ✘ Mvp Music » Database ✘ ] Błąd podczas zapisywania danych w tabeli \""...Table_Main..."\": %s", sError);
		return;
	}
	g_eInfo[iClient].bIsDataLoaded = true;
}


/* [ Helpers ] */
void LoadConfig() {
	char sPath[PLATFORM_MAX_PATH], sBuffer[PLATFORM_MAX_PATH], sSoundPath[PLATFORM_MAX_PATH];
	KeyValues kvKeyValues = new KeyValues("Pawel Mvp Music - Config");
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/pPlugins/pMvpMusic.cfg");
	if (!kvKeyValues.ImportFromFile(sPath)) {
		if (!FileExists(sPath)) {
			if (GenerateConfig())
				LoadConfig();
			else
				SetFailState("[ ✘ Mvp Music » Config ✘ ] Nie udało się utworzyć pliku konfiguracyjnego!");
			delete kvKeyValues;
			return;
		}
		else {
			LogError("[ ✘ Mvp Music » Config ✘ ] Aktualny plik konfiguracyjny jest uszkodzony! Trwa tworzenie nowego...");
			if (GenerateConfig())
				LoadConfig();
			else
				SetFailState("[ ✘ Mvp Music » Config ✘ ] Nie udało się utworzyć pliku konfiguracyjnego!");
			delete kvKeyValues;
			return;
		}
	}
	if (kvKeyValues.JumpToKey("Ustawienia")) {
		g_iCvar = kvKeyValues.GetNum("Enable_Random_Sound");
		kvKeyValues.GetString("Menu_Tag", g_sMenuTag, sizeof(g_sMenuTag));
		kvKeyValues.GetString("Chat_Tag", g_sChatTag, sizeof(g_sChatTag));
		kvKeyValues.GoBack();
	}
	if (kvKeyValues.JumpToKey("Piosenki")) {
		kvKeyValues.GotoFirstSubKey();
		do {
			kvKeyValues.GetString("Path", sBuffer, sizeof(sBuffer));
			Format(sSoundPath, sizeof(sSoundPath), "sound/%s", sBuffer);
			if (FileExists(sSoundPath)) {
				g_arSounds[2].PushString(sBuffer);
				PrecacheSoundAny(sBuffer);
				AddFileToDownloadsTable(sSoundPath);
				g_arSounds[0].Push(g_arSounds[0].Length + 1);
				kvKeyValues.GetSectionName(sBuffer, sizeof(sBuffer));
				g_arSounds[1].PushString(sBuffer);
				kvKeyValues.GetString("Flags", sBuffer, sizeof(sBuffer));
				g_arSounds[3].PushString(sBuffer);
			}
		}
		while (kvKeyValues.GotoNextKey());
		kvKeyValues.GoBack();
	}
	if (!g_arSounds[0].Length)
		SetFailState("[ ✘ Mvp Music » Config ✘ ] Nie wykryto żadnej piosenki w configu!");
	LoadRandomSounds();
	delete kvKeyValues;
}

bool GenerateConfig() {
	KeyValues kvKeyValues = new KeyValues("Pawel Mvp Music - Config");
	char sPath[PLATFORM_MAX_PATH];
	char sDirectory[PLATFORM_MAX_PATH] = "configs/pPlugins/";
	BuildPath(Path_SM, sPath, sizeof(sPath), sDirectory);
	if (!DirExists(sPath)) {
		CreateDirectory(sPath, 504);
		if (!DirExists(sPath))
			SetFailState("Nie udało się utworzyć katalogu /sourcemod/configs/pPlugins/ . Proszę to zrobić ręcznie.");
	}
	BuildPath(Path_SM, sPath, sizeof(sPath), "%spMvpMusic.cfg", sDirectory);
	if (kvKeyValues.JumpToKey("Ustawienia", true)) {
		kvKeyValues.SetString("Enable_Random_Sound", "1");
		kvKeyValues.SetString("Menu_Tag", "PluginyCS.pl");
		kvKeyValues.SetString("Chat_Tag", "{orange}PluginyCS.pl {grey}»{default}");
		kvKeyValues.GoBack();
	}
	if (kvKeyValues.JumpToKey("Piosenki", true)) {
		kvKeyValues.GotoFirstSubKey();
		if (kvKeyValues.JumpToKey("Dua Lipa - Blow Your Mind", true)) {
			kvKeyValues.SetString("Path", "pawel_mvp/res_01.mp3");
			kvKeyValues.SetString("Flags", "ao");
			kvKeyValues.GoBack();
		}
		kvKeyValues.GoBack();
	}
	kvKeyValues.Rewind();
	bool bResult = kvKeyValues.ExportToFile(sPath);
	delete kvKeyValues;
	return bResult;
}

void LoadRandomSounds() {
	char sPath[PLATFORM_MAX_PATH], sBuffer[PLATFORM_MAX_PATH];
	KeyValues kvKeyValues = new KeyValues("Pawel Mvp Music - Config");
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/pPlugins/pMvpMusic.cfg");
	kvKeyValues.ImportFromFile(sPath);
	if (kvKeyValues.JumpToKey("Piosenki")) {
		kvKeyValues.GotoFirstSubKey();
		do {
			g_arRandom[0].Push(g_arRandom[0].Length + 1);
			kvKeyValues.GetSectionName(sBuffer, sizeof(sBuffer));
			g_arRandom[1].PushString(sBuffer);
			kvKeyValues.GetString("Path", sBuffer, sizeof(sBuffer));
			g_arRandom[2].PushString(sBuffer);
		}
		while (kvKeyValues.GotoNextKey());
		kvKeyValues.GoBack();
	}
	delete kvKeyValues;
}

int CheckDrawType(int iClient, char[] sFlags, int iSoundId) {
	if (g_eInfo[iClient].iSound == iSoundId)return ITEMDRAW_DISABLED;
	if (CheckFlags(iClient, sFlags))return ITEMDRAW_DEFAULT;
	return ITEMDRAW_DISABLED;
}

bool IsValidClient(int iClient) {
	if (iClient <= 0)return false;
	if (iClient > MaxClients)return false;
	if (!IsClientConnected(iClient))return false;
	if (IsFakeClient(iClient))return false;
	if (IsClientSourceTV(iClient))return false;
	return IsClientInGame(iClient);
}

void CreateArrays() {
	for (int i = 0; i < 4; i++) {
		g_arSounds[i] = new ArrayList(128);
		if (i < 3)
			g_arRandom[i] = new ArrayList(128);
	}
}

void ClearArrays() {
	for (int i = 0; i < 4; i++) {
		g_arSounds[i].Clear();
		if (i < 3)
			g_arRandom[i].Clear();
	}
}

void GetRandomSound() {
	if (!g_arRandom[0].Length)
		LoadRandomSounds();
	int iRandom = GetRandomInt(0, g_arRandom[0].Length - 1);
	char sPath[128], sSound[128];
	g_arRandom[1].GetString(iRandom, sSound, sizeof(sSound));
	g_arRandom[2].GetString(iRandom, sPath, sizeof(sPath));
	PrecacheSoundAny(sPath);
	LoopClients(i) {
		if (g_eInfo[i].bEnabled && g_eInfo[i].fVolume) {
			ClientCommand(i, "playgamesound Music.StopAllMusic");
			CPrintToChat(i, "%s Aktualnie leci piosenka {lime}%s{default}.", g_sChatTag, sSound);
			EmitSoundToClientAny(i, sPath, -2, 0, 0, 0, g_eInfo[i].fVolume, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		}
	}
}

bool CheckFlags(int iClient, char[] sFlags) {
	if (GetUserFlagBits(iClient) & ADMFLAG_ROOT)return true;
	int iCount = CountCharacters(sFlags);
	int iAccess = 0;
	char sFlag[16];
	for (int i = 0; i < iCount; i++) {
		Format(sFlag, sizeof(sFlag), "%c", sFlags[i]);
		if (GetUserFlagBits(iClient) & ReadFlagString(sFlag))
			iAccess++;
	}
	if (iAccess == iCount)
		return true;
	if (StrEqual(sFlags, ""))return true;
	return false;
}

int CountCharacters(char[] sPhrase) {
	int iCharacters = 0;
	for (int i = 0; i < strlen(sPhrase); i++)
	iCharacters++;
	return iCharacters;
} 