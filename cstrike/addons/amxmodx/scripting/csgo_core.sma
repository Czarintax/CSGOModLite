#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <sqlx>
#include <csgomod>

#define PLUGIN	"CS:GO Mod Core"
#define AUTHOR	"O'Zone & Czarintax"

#pragma dynamic 65536
#pragma semicolon 1

#define ADMIN_FLAG		ADMIN_ADMIN
#define FIELD_PLAYER	var_iuser3
#define TASK_DATA		2592
#define TASK_AD			4234

enum _:playerInfo { Float:MONEY, bool:DATA_LOADED, bool:HUD_BLOCKED, NAME[32], SAFE_NAME[64], AUTH_ID[65], IP[32] };

new playerData[MAX_PLAYERS + 1][playerInfo], Handle:sql, Handle:connection, saveType, Float:killReward, Float:killHSReward, Float:bombReward, Float:defuseReward, Float:hostageReward, Float:winReward,
	Float:botMultiplier, Float:vipMultiplier, Float:svipMultiplier, minPlayers, minPlayerFilter, bool:end, bool:sqlConnected, sqlHost[64], sqlUser[64], sqlPassword[64], sqlDatabase[64], resetHandle;

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);

	register_cvar("csgo_version", VERSION, FCVAR_SERVER);

	register_dictionary("csgomod.txt");

	bind_pcvar_string(create_cvar("csgo_sql_host", "", FCVAR_SPONLY | FCVAR_PROTECTED), sqlHost, charsmax(sqlHost));
	bind_pcvar_string(create_cvar("csgo_sql_user", "", FCVAR_SPONLY | FCVAR_PROTECTED), sqlUser, charsmax(sqlUser));
	bind_pcvar_string(create_cvar("csgo_sql_pass", "", FCVAR_SPONLY | FCVAR_PROTECTED), sqlPassword, charsmax(sqlPassword));
	bind_pcvar_string(create_cvar("csgo_sql_db", "", FCVAR_SPONLY | FCVAR_PROTECTED), sqlDatabase, charsmax(sqlDatabase));

	bind_pcvar_num(create_cvar("csgo_save_type", "0"), saveType);
	bind_pcvar_num(create_cvar("csgo_min_players", "4"), minPlayers);
	bind_pcvar_num(create_cvar("csgo_min_player_filter", "0"), minPlayerFilter);
	bind_pcvar_float(create_cvar("csgo_kill_reward", "0.35"), killReward);
	bind_pcvar_float(create_cvar("csgo_kill_hs_reward", "0.15"), killHSReward);
	bind_pcvar_float(create_cvar("csgo_bomb_reward", "2.0"), bombReward);
	bind_pcvar_float(create_cvar("csgo_defuse_reward", "2.0"), defuseReward);
	bind_pcvar_float(create_cvar("csgo_hostages_reward", "2.0"), hostageReward);
	bind_pcvar_float(create_cvar("csgo_round_reward", "0.5"), winReward);
	bind_pcvar_float(create_cvar("csgo_multiplier_vip", "1.25"), vipMultiplier);
	bind_pcvar_float(create_cvar("csgo_multiplier_svip", "1.5"), svipMultiplier);
	bind_pcvar_float(create_cvar("csgo_multiplier_bot", "0.5"), botMultiplier);

	register_concmd("csgo_reset_data", "cmd_reset_data", ADMIN_FLAG);
	register_concmd("csgo_add_balance", "cmd_add_money", ADMIN_FLAG, "<player> <amount>");

	RegisterHookChain(RG_CSGameRules_PlayerKilled, "CSGameRules_PlayerKilled_Post", 1);
	RegisterHookChain(RG_PlantBomb, "PlantBomb", 1);
	RegisterHookChain(RG_CGrenade_DefuseBombEnd, "CGrenade_DefuseBombEnd", 1);
	RegisterHookChain(RG_RoundEnd, "RoundEnd_Post", 1);
	RegisterHookChain(RG_CBasePlayer_AddAccount, "CBasePlayer_AddAccount", 1);
	
	register_message(SVC_INTERMISSION, "message_intermission");

	resetHandle = CreateMultiForward("csgo_reset_data", ET_IGNORE);
}

public plugin_cfg()
{
	new configPath[64], host[64], user[64], pass[64], db[64], error[256], errorNum;

	get_localinfo("amxx_configsdir", configPath, charsmax(configPath));

	server_cmd("exec %s/csgo_mod.cfg", configPath);
	server_exec();

	get_cvar_string("csgo_sql_host", host, charsmax(host));
	get_cvar_string("csgo_sql_user", user, charsmax(user));
	get_cvar_string("csgo_sql_pass", pass, charsmax(pass));
	get_cvar_string("csgo_sql_db", db, charsmax(db));

	sql = SQL_MakeDbTuple(host, user, pass, db);

	connection = SQL_Connect(sql, errorNum, error, charsmax(error));

	if (errorNum) {
		log_to_file("csgo-error.log", "[CS:GO Mod] Init SQL Error: %s (%i)", error, errorNum);

		return;
	}

	new queryData[512], bool:hasError;


	formatex(queryData, charsmax(queryData), "CREATE TABLE IF NOT EXISTS `csgo_data` (name VARCHAR(64), ip VARCHAR(32), authid VARCHAR(65), money FLOAT NOT NULL DEFAULT 0, online INT NOT NULL DEFAULT 0, PRIMARY KEY(authid, name));");

	new Handle:query = SQL_PrepareQuery(connection, queryData);

	if (!SQL_Execute(query)) {
		SQL_QueryError(query, error, charsmax(error));

		log_to_file("csgo-error.log", "[CS:GO Mod] Init SQL Error: %s", error);

		hasError = true;
	}

	formatex(queryData, charsmax(queryData), "ALTER TABLE `csgo_data` ADD COLUMN hud INT NOT NULL DEFAULT 0;");

	query = SQL_PrepareQuery(connection, queryData);

	SQL_Execute(query);

	SQL_FreeHandle(query);

	if (!hasError) sqlConnected = true;
}

public plugin_natives()
{
	register_native("csgo_get_money", "_csgo_get_money", 1);
	register_native("csgo_add_money", "_csgo_add_money", 1);
	register_native("csgo_set_money", "_csgo_set_money", 1);

	register_native("csgo_get_hud", "_csgo_get_hud", 1);
	register_native("csgo_get_min_players", "_csgo_get_min_players", 0);
}

public plugin_end()
{
	SQL_FreeHandle(sql);
	SQL_FreeHandle(connection);
}

public client_disconnected(id)
{
	save_data(id, end ? 2 : 1);

	remove_task(id + TASK_DATA);
}

public client_putinserver(id)
{
	playerData[id][MONEY] = 0.0;

	if (is_user_hltv(id) || is_user_bot(id)) return;

	get_user_authid(id, playerData[id][AUTH_ID], charsmax(playerData[][AUTH_ID]));
	get_user_name(id, playerData[id][NAME], charsmax(playerData[][NAME]));
	get_user_ip(id, playerData[id][IP], charsmax(playerData[][IP]));

	mysql_escape_string(playerData[id][NAME], playerData[id][SAFE_NAME], charsmax(playerData[][SAFE_NAME]));

	set_task(0.1, "load_data", id + TASK_DATA);
	set_task(15.0, "show_advertisement", id + TASK_AD);
}

public show_advertisement(id)
{
	id -= TASK_AD;

	client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_INFO_CREATED", PLUGIN, VERSION, AUTHOR);
	client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_INFO_HELP");
}

public cmd_add_money(id)
{
	if (!csgo_check_account(id) || !(get_user_flags(id) & ADMIN_FLAG))
		return PLUGIN_HANDLED;

	new playerName[32], tempMoney[5];

	read_argv(1, playerName, charsmax(playerName));
	read_argv(2, tempMoney, charsmax(tempMoney));

	new Float:addedMoney = str_to_float(tempMoney), player = cmd_target(id, playerName, 0);

	if (!player) {
		console_print(id, ^"%s %L", CONSOLE_PREFIX, id, "CSGO_CORE_ADD_MONEY_NO_PLAYER");

		return PLUGIN_HANDLED;
	}

	if (addedMoney < 0.1) {
		console_print(id, ^"%s %L", CONSOLE_PREFIX, id, "CSGO_CORE_ADD_MONEY_TOO_LOW");

		return PLUGIN_HANDLED;
	}

	playerData[player][MONEY] += addedMoney;

	save_data(player);
#if defined XASH3D
	client_print(player, print_chat, ^"%s %L", CHAT_PREFIX, id, "CSGO_CORE_ADD_MONEY_GIVE", playerData[id][NAME], addedMoney);
	client_print(id, print_chat, ^"%s %L", CHAT_PREFIX, id, "CSGO_CORE_ADD_MONEY_GIVE2", addedMoney, playerData[player][NAME]);
#else
	client_print_color(player, player, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_ADD_MONEY_GIVE", playerData[id][NAME], addedMoney);
	client_print_color(id, id, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_ADD_MONEY_GIVE2", addedMoney, playerData[player][NAME]);
#endif
	log_to_file("csgo-admin.log", "%s gave %.2f euros to player %s.", playerData[id][NAME], addedMoney, playerData[player][NAME]);

	return PLUGIN_HANDLED;
}

public cmd_reset_data(id)
{
	if (!csgo_check_account(id) || !(get_user_flags(id) & ADMIN_FLAG))
		return PLUGIN_HANDLED;

	log_to_file("csgo-admin.log", "Admin %s forced full data reset.", PLUGIN, playerData[id][NAME]);
#if defined XASH3D
	client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_RESET_INFO");
	client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_RESET_INFO2");
#else
	client_print_color(id, id, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_RESET_INFO");
	client_print_color(id, id, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_RESET_INFO2");
#endif
	clear_database(id);

	new ret;

	ExecuteForward(resetHandle, ret);

	set_task(10.0, "restart_map");

	return PLUGIN_HANDLED;
}

public clear_database(id)
{
	for (new i = 1; i <= MAX_PLAYERS; i++) playerData[id][DATA_LOADED] = false;

	sqlConnected = false;

	new tempData[32];

	formatex(tempData, charsmax(tempData), "DROP TABLE `csgo_core`;");

	SQL_ThreadQuery(sql, "ignore_handle", tempData);
}

public restart_map()
{
	new currentMap[64];

	get_mapname(currentMap, charsmax(currentMap));

	server_cmd("changelevel ^"%s^"", currentMap);
}

public CSGameRules_PlayerKilled_Post(victim, killer)
{
	if (!is_user_connected(killer) || !is_user_connected(victim) || !is_user_alive(killer) || get_member(victim, m_iTeam) == get_member(killer, m_iTeam) || !csgo_get_min_players())
		return HC_CONTINUE;

	playerData[killer][MONEY] += killReward * get_multiplier(killer, victim);

	if (get_member(victim, m_bHeadshotKilled)) playerData[killer][MONEY] += killHSReward * get_multiplier(killer, victim);

	save_data(killer);

	return HC_CONTINUE;
}

public PlantBomb(id, Float:vecStart[3], Float:vecVelocity[3])
{
	if (!csgo_get_min_players()) return;
	
	new Float:money = bombReward * get_multiplier(id);

	playerData[id][MONEY] += money;
#if defined XASH3D
	client_print(id, print_chat, ^"%s %L", CHAT_PREFIX, id, "CSGO_CORE_BOMB_PLANTED", money);
#else
	client_print_color(id, id, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_BOMB_PLANTED", money);
#endif
	save_data(id);
}

public CGrenade_DefuseBombEnd(const this, const id, bool:bDefused)
{
	if (!csgo_get_min_players() || !bDefused) return;

	new Float:money = defuseReward * get_multiplier(id);

	playerData[id][MONEY] += money;
#if defined XASH3D
	client_print(id, print_chat, ^"%s %L", CHAT_PREFIX, id, "CSGO_CORE_BOMB_DEFUSED", money);
#else
	client_print_color(id, id, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_BOMB_DEFUSED", money);
#endif
	save_data(id);
}

public RoundEnd_Post(WinStatus:status, ScenarioEventEndRound:event, Float:tmDelay)
{
	if(status != WINSTATUS_CTS && status != WINSTATUS_TERRORISTS) {
		return HC_CONTINUE;
	}
	
	if (!csgo_get_min_players()) {
		return HC_CONTINUE;
	}
	
	new players[MAX_PLAYERS], num;
	get_players(players, num, "ch");

	for(new i, player; i < num; i++) {
		player = players[i];

		switch(get_member(player, m_iTeam)) {
			case TEAM_CT: {
				if(status == WINSTATUS_CTS) {
					new Float:money = winReward * get_multiplier(player);

					playerData[player][MONEY] += money;
#if defined XASH3D
					client_print(player, print_chat, ^"%s %L", CHAT_PREFIX, player, "CSGO_CORE_ROUND_WIN", money);
#else
					client_print_color(player, player, "%s %L", CHAT_PREFIX, player, "CSGO_CORE_ROUND_WIN", money);
#endif
					save_data(player);
				}
			}
			case TEAM_TERRORIST: {
				if(status == WINSTATUS_TERRORISTS) {
					new Float:money = winReward * get_multiplier(player);

					playerData[player][MONEY] += money;
#if defined XASH3D
					client_print(player, print_chat, ^"%s %L", CHAT_PREFIX, player, "CSGO_CORE_ROUND_WIN", money);
#else
					client_print_color(player, player, "%s %L", CHAT_PREFIX, player, "CSGO_CORE_ROUND_WIN", money);
#endif
					save_data(player);
				}
			}
		}
	}
	
	return HC_CONTINUE;
}

public CBasePlayer_AddAccount(const id, amount, RewardType:type, bool:bTrackChange)
{
	if (type == RT_HOSTAGE_RESCUED)
	{
		if (csgo_get_min_players())
		{
			new Float:money = hostageReward * get_multiplier(id);
			
			playerData[id][MONEY] += money;
#if defined XASH3D
			client_print(id, print_chat, ^"%s %L", CHAT_PREFIX, id, "CSGO_CORE_HOSTAGES_RESCUED", money);
#else
			client_print_color(id, id, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_HOSTAGES_RESCUED", money);
#endif
			save_data(id);
		}
	}
	
	return HC_CONTINUE;
}

public message_intermission()
{
	end = true;

	for (new id = 1; id <= MAX_PLAYERS; id++) {
		if (!is_user_connected(id) || is_user_hltv(id) || is_user_bot(id)) continue;

		new Float:money;

		playerData[id][MONEY] += (money = random_float(1.0, 3.0));
#if defined XASH3D
		client_print(id, print_chat, ^"%s %L", CHAT_PREFIX, id, "CSGO_CORE_MAP_REWARD", money);
#else
		client_print_color(id, id, "%s %L", CHAT_PREFIX, id, "CSGO_CORE_MAP_REWARD", money);
#endif
		save_data(id, 1);
	}

	return PLUGIN_CONTINUE;
}

public load_data(id)
{
	if (!sqlConnected) {
		set_task(1.0, "load_data", id);

		return;
	}

	id -= TASK_DATA;

	new playerId[1], queryData[256];

	playerId[0] = id;

	switch (saveType) {
		case SAVE_NAME: formatex(queryData, charsmax(queryData), "SELECT * FROM `csgo_data` WHERE `name` = ^"%s^" LIMIT 1;", playerData[id][SAFE_NAME]);
		case SAVE_AUTH_ID: formatex(queryData, charsmax(queryData), "SELECT * FROM `csgo_data` WHERE `authid` = ^"%s^" LIMIT 1;", playerData[id][AUTH_ID]);
	}

	SQL_ThreadQuery(sql, "load_data_handle", queryData, playerId, sizeof(playerId));
}

public load_data_handle(failState, Handle:query, error[], errorNum, playerId[], dataSize)
{
	if (failState) {
		log_to_file("csgo-error.log", "[CS:GO] SQL Error: %s (%d)", error, errorNum);

		return;
	}

	new id = playerId[0];

	if (SQL_MoreResults(query)) {
		SQL_ReadResult(query, SQL_FieldNameToNum(query, "money"), playerData[id][MONEY]);

		if (SQL_ReadResult(query, SQL_FieldNameToNum(query, "hud"))) playerData[id][HUD_BLOCKED] = false;
	} else {
		new queryData[512];

		formatex(queryData, charsmax(queryData), "INSERT INTO `csgo_data` (`name`, `ip`, `authid`, `money`, `hud`, `online`) VALUES (^"%s^",^"%s^",^"%s^", '0', '0', '0') ON DUPLICATE KEY UPDATE name=name",
			playerData[id][SAFE_NAME], playerData[id][IP], playerData[id][AUTH_ID]);

		SQL_ThreadQuery(sql, "ignore_handle", queryData);
	}
	
	playerData[id][DATA_LOADED] = true;

	save_data(id);
}

stock save_data(id, end = 0)
{
	if (!playerData[id][DATA_LOADED]) return;

	new queryData[512];

	switch (saveType) {
		case SAVE_NAME: {
			formatex(queryData, charsmax(queryData), "UPDATE `csgo_data` SET `money` = %f, `hud` = %i, `online` = %i, `authid` = ^"%s^", `ip` = ^"%s^" WHERE `name` = ^"%s^";",
				playerData[id][MONEY], playerData[id][HUD_BLOCKED], end ? 0 : 1, playerData[id][AUTH_ID], playerData[id][IP], playerData[id][SAFE_NAME]);
		}
		case SAVE_AUTH_ID: {
			formatex(queryData, charsmax(queryData), "UPDATE `csgo_data` SET `money` = %f, `hud` = %i, `online` = %i, `name` = ^"%s^", `ip` = ^"%s^" WHERE `authid` = ^"%s^";",
				playerData[id][MONEY], playerData[id][HUD_BLOCKED], end ? 0 : 1, playerData[id][SAFE_NAME], playerData[id][IP], playerData[id][AUTH_ID]);
		}
	}

	switch (end) {
		case 0, 1: SQL_ThreadQuery(sql, "ignore_handle", queryData);
		case 2: {
			static error[128], errorNum, Handle:query;

			query = SQL_PrepareQuery(connection, queryData);

			if (!SQL_Execute(query)) {
				errorNum = SQL_QueryError(query, error, charsmax(error));

				log_to_file("csgo-error.log", "Save Query Nonthreaded failed. [%d] %s", errorNum, error);

				SQL_FreeHandle(query);

				return;
			}

			SQL_FreeHandle(query);
		}
	}

	if (end) playerData[id][DATA_LOADED] = false;
}

public ignore_handle(failState, Handle:query, error[], errorNum, data[], dataSize)
{
	if (failState) {
		if (failState == TQUERY_CONNECT_FAILED) {
			log_to_file("csgo-error.log", "[CS:GO] Could not connect to SQL database. [%d] %s", errorNum, error);
		} else if (failState == TQUERY_QUERY_FAILED) {
			log_to_file("csgo-error.log", "[CS:GO] Query failed. [%d] %s", errorNum, error);
		}
	}

	return PLUGIN_CONTINUE;
}

public Float:_csgo_get_money(id)
	return Float:playerData[id][MONEY];

public _csgo_add_money(id, Float:amount)
{
	playerData[id][MONEY] = floatmax(0.0, playerData[id][MONEY] + amount);

	save_data(id);
}

public _csgo_set_money(id, Float:amount)
{
	playerData[id][MONEY] = floatmax(0.0, amount);

	save_data(id);
}

public _csgo_get_hud(id)
	return !playerData[id][HUD_BLOCKED];

public bool:_csgo_get_min_players()
{
	static playersCount;

	switch (minPlayerFilter) {
		case 0: playersCount = get_playersnum_ex(GetPlayers_None);
		case 1: playersCount = get_playersnum_ex(GetPlayers_ExcludeBots);
		case 2: playersCount = get_playersnum_ex(GetPlayers_ExcludeHLTV);
		case 3: playersCount = get_playersnum_ex(GetPlayers_ExcludeBots|GetPlayers_ExcludeHLTV);
	}

	return playersCount >= minPlayers;
}

stock Float:get_multiplier(id, target = 0)
{
	if (is_user_bot(target)) return botMultiplier;
	else if (csgo_get_user_svip(id)) return svipMultiplier;
	else if (csgo_get_user_vip(id)) return vipMultiplier;
	else return 1.0;
}
