module("luci.controller.cjdns", package.seeall)

cjdns  = require "cjdns/init"
dkjson = require "dkjson"

function index()
	if not nixio.fs.access("/etc/config/cjdns") then
		return
	end

	entry({"admin", "services", "cjdns"},
		cbi("cjdns/overview"), _("cjdns")).dependent = true

	entry({"admin", "services", "cjdns", "overview"},
		cbi("cjdns/overview"), _("Overview"), 1).leaf = false

	entry({"admin", "services", "cjdns", "peering"},
		cbi("cjdns/peering"), _("Peers"), 2).leaf = false

	entry({"admin", "services", "cjdns", "iptunnel"},
		cbi("cjdns/iptunnel"), _("IP Tunnel"), 3).leaf = false

	entry({"admin", "services", "cjdns", "settings"},
		cbi("cjdns/settings"), _("Settings"), 4).leaf = false

	entry({"admin", "services", "cjdns", "cjdrouteconf"},
		cbi("cjdns/cjdrouteconf"), _("cjdroute.conf"), 5).leaf = false

	entry({"admin", "services", "cjdns", "peers"}, call("act_peers")).leaf = true
	entry({"admin", "services", "cjdns", "ping"}, call("act_ping")).leaf = true
end

function act_peers()
	require("cjdns/uci")
	admin = cjdns.uci.makeInterface()

	local page = 0
	local peers = {}

	while page do
		local response, err = admin:auth({
			q = "InterfaceController_peerStats",
			page = page
		})

		if err or response.error then
			luci.http.status(502, "Bad Gateway")
			luci.http.prepare_content("application/json")
			luci.http.write_json({ err = err, response = response })
			return
		end

		for i,peer in pairs(response.peers) do
			local peertable = peerstats_join(peer.addr)
			peer.ipv6 = peertable['ipv6']
			peer.version = peertable['version']
			peer.label = peertable['label']
			peer.pubkey = peertable['pubkey']
			uci.cursor():foreach("cjdns", "udp_peer", function(udp_peer)
				if peer.pubkey == udp_peer.public_key then
					peer.user = udp_peer.user
				end
			end)
			peers[#peers + 1] = peer
		end

		if response.more then
			page = page + 1
		else
			page = nil
		end
	end

	luci.http.status(200, "OK")
	luci.http.prepare_content("application/json")
	luci.http.write_json(peers)
end

function act_ping()
	require("cjdns/uci")
	admin = cjdns.uci.makeInterface()

	local response, err = admin:auth({
		q = "SwitchPinger_ping",
		path = luci.http.formvalue("label"),
		timeout = tonumber(luci.http.formvalue("timeout"))
	})

	if err or response.error then
		luci.http.status(502, "Bad Gateway")
		luci.http.prepare_content("application/json")
		luci.http.write_json({ err = err, response = response })
		return
	end

	luci.http.status(200, "OK")
	luci.http.prepare_content("application/json")
	luci.http.write_json(response)
end

function peerstats_join(addrLine)
    local pubkey = addrLine:sub(addrLine:len() - 53)
    local process = io.popen("/usr/bin/publictoip6 " .. pubkey, "r")
    local ipv6 = process:read()
    local label = 'label'
    process:close()
    local version = addrLine:match("^(v%w+)%.") or 'v0'
    local label = addrLine:sub(version:len() + 2, version:len() + 20)
    return { pubkey=pubkey, ipv6=ipv6, label=label, version=version }
end