// https://github.com/perilouswithadollarsign/cstrike15_src/blob/f82112a2388b841d72cb62ca48ab1846dfcc11c8/common/proto_oob.h#L79
#define A2S_GETCHALLENGE 'q'
// https://github.com/perilouswithadollarsign/cstrike15_src/blob/f82112a2388b841d72cb62ca48ab1846dfcc11c8/public/tier1/netadr.h#L26
#define NA_IP             3

#define ADDRESS(%1) view_as<Address>(%1)
#define INVALID_OFFSET ADDRESS(-1)

enum struct netadr_s_offsets
{
	Address type;
	Address ip;
	Address port;
}

enum struct netpacket_t_offsets
{
	Address from;
	Address data;
	Address size;
}

enum struct NetOffsets
{
	netadr_s_offsets nao;
	netpacket_t_offsets npo;
}
static NetOffsets offsets;

methodmap Netadr_s
{
	property int type
	{
		public get() { return LoadFromAddress(ADDRESS(this) + offsets.nao.type, NumberType_Int32); }
	}
	
	property int ip
	{
		public get() { return LoadFromAddress(ADDRESS(this) + offsets.nao.ip, NumberType_Int32); }
	}
	
	property int port
	{
		public get() { return LoadFromAddress(ADDRESS(this) + offsets.nao.port, NumberType_Int16); }
	}
	
	public void ToString(char[] buff, int size)
	{
		int ip = this.ip;
		Format(buff, size, "%i.%i.%i.%i", ip & 0xFF, ip >> 8 & 0xFF, ip >> 16 & 0xFF, ip >>> 24);
	}
}

methodmap Netpacket_t
{
	public Netpacket_t(Address packet_address)
	{
		return view_as<Netpacket_t>(packet_address);
	}

	property Netadr_s from
	{
		public get() { return view_as<Netadr_s>(ADDRESS(this) + offsets.npo.from); }
	}
	
	property Address data
	{
		public get() { return LoadFromAddress(ADDRESS(this) + offsets.npo.data, NumberType_Int32); }
	}
	
	property int size
	{
		public get() { return LoadFromAddress(ADDRESS(this) + offsets.npo.size, NumberType_Int32); }
	}

	property char a2s_identifier
	{
		public get() { return LoadFromAddress(this.data + ADDRESS(4), NumberType_Int8); }
	}
}

void SetupNet(GameData gamedata)
{
	// netadr_s
	if ((offsets.nao.type = ADDRESS(gamedata.GetOffset("netadr_s::type"))) == INVALID_OFFSET)
	{
		SetFailState("Couldn't find 'netadr_s::type'. (missing from the gamedata)");
	}
	
	if ((offsets.nao.ip = ADDRESS(gamedata.GetOffset("netadr_s::ip"))) == INVALID_OFFSET)
	{
		SetFailState("Couldn't find 'netadr_s::ip'. (missing from the gamedata)");
	}

	if ((offsets.nao.port = ADDRESS(gamedata.GetOffset("netadr_s::port"))) == INVALID_OFFSET)
	{
		SetFailState("Couldn't find 'netadr_s::port'. (missing from the gamedata)");
	}
	
	// netpacket_t
	if ((offsets.npo.from = ADDRESS(gamedata.GetOffset("netpacket_t::from"))) == INVALID_OFFSET)
	{
		SetFailState("Couldn't find 'netpacket_t::from'. (missing from the gamedata)");
	}

	if ((offsets.npo.data = ADDRESS(gamedata.GetOffset("netpacket_t::data"))) == INVALID_OFFSET)
	{
		SetFailState("Couldn't find 'netpacket_t::data'. (missing from the gamedata)");
	}

	if ((offsets.npo.size = ADDRESS(gamedata.GetOffset("netpacket_t::size"))) == INVALID_OFFSET)
	{
		SetFailState("Couldn't find 'netpacket_t::size'. (missing from the gamedata)");
	}
}