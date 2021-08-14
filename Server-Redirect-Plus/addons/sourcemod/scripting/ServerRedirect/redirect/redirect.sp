StringMap g_ShouldReconnect;
Handle g_RejectConnection;

void SetupSDKCalls(GameData gamedata)
{
	// void CBaseServer::RejectConnection( const ns_address &adr, const char *fmt, ... )
	StartPrepSDKCall(SDKCall_Static);
	
	if (!PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CBaseServer::RejectConnection"))
	{
		SetFailState("Couldn't find 'CBaseServer::RejectConnection' signature. (missing from the gamedata)");
	} 
	
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); 	// CBaseServer |this|
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); 	// const ns_address &adr
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);		// const char *fmt

	if(!(g_RejectConnection = EndPrepSDKCall()))
	{
		SetFailState("Failed to create SDKCall for 'CBaseServer::RejectConnection'.");
	}
}

void SetupDhooks(GameData gamedata)
{
	// bool CBaseServer::ProcessConnectionlessPacket(netpacket_t * packet)
	DynamicDetour detour = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Bool, ThisPointer_Address);
	
	if (!DHookSetFromConf(detour, gamedata, SDKConf_Signature, "CBaseServer::ProcessConnectionlessPacket"))
	{
		SetFailState("Couldn't find 'CBaseServer::ProcessConnectionlessPacket' signature. (missing from the gamedata)")
	}

	// netpacket_t * packet
	detour.AddParam(HookParamType_ObjectPtr);
	
	if (!detour.Enable(Hook_Pre, ProcessConnectionlessPacket_Dhook))
	{
		SetFailState("Couldn't detour 'CBaseServer::ProcessConnectionlessPacket'");
	}
}

MRESReturn ProcessConnectionlessPacket_Dhook(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	// No one needs to be redirected so there is no point checking packets.
	if (!g_ShouldReconnect.Size)
	{
		return MRES_Ignored;
	}

	// Get packet.
	Netpacket_t packet = Netpacket_t(hParams.GetAddress(1));
	
	// Check if it's long enough to be the right packet.
	if (packet.size < 5)
	{
		return MRES_Ignored;
	}

	// Make sure the packet is a 'A2S_GETCHALLENGE'.
	if (packet.a2s_identifier != A2S_GETCHALLENGE)
	{
		return MRES_Ignored;
	}

	// Get the address that the packet was sent from.
	Netadr_s from = packet.from;
	
	// If the packet is unknown, there is no way to check who is it, don't continue.
	if (from.type != NA_IP)
	{
		return MRES_Ignored;
	}

	// from_str: XXX.XXX.XXX.XXX\0 = 16 characters.
	// redirect_dest: can be either an IP or a domain, domain can be as long as 255 characters. (+ '\0')
	char from_str[16], redirect_dest[256];
	from.ToString(from_str, sizeof(from_str));
	
	// Check if the client is in the redirect queue.
	if (g_ShouldReconnect.GetString(from_str, redirect_dest, sizeof(redirect_dest)))
	{
		// Redirect the client
		RejectConnection(pThis, packet, redirect_dest);

		// Remove from redirect queue.
		g_ShouldReconnect.Remove(from_str);
		
		// Set return value of the function to 1.
		DHookSetReturn(hReturn, 1);
		
		// Skip real function.
		return MRES_Supercede;
	}
	
	// Client is not in the redirect queue, continue normally.
	return MRES_Ignored;
}

void RejectConnection(Address pThis, Netpacket_t packet, const char[] redirect_dest)
{
	// 'ConnectRedirectAddress:' length = 23
	// IP / Domain max length = 255
	// \n = 1
	// '\0' = 1
	char redirect_msg[23 + 255 + 1 + 1];

	// Format reject reason to redirect.
	Format(redirect_msg, sizeof(redirect_msg), "ConnectRedirectAddress:%s\n", redirect_dest);

	// Send reject connection.
	SDKCall(g_RejectConnection, pThis, packet, redirect_msg);
}

void RedirectClient(int client, const char[] ip)
{
	// XXX.XXX.XXX.XXX\0 = 16 characters.
	char client_ip[16];
	GetClientIP(client, client_ip, sizeof(client_ip));

	// Add to redirection queue.
	g_ShouldReconnect.SetString(client_ip, ip);

	// Force retry to redirect.
	ClientCommand(client, "retry");
}