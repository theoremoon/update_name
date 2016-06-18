/* update_name 
   Copyright theoldmoon0602
   MIT LISENCE
*/
import	std.stdio,
		std.regex,
		std.json,
		std.file,
		std.conv,
		std.uni,
		std.utf,
		std.encoding,
		std.algorithm,
		std.range,
		std.datetime,
		core.thread,
		std.experimental.logger,
		std.getopt;
import  twitter4d;

string logfile = "update_name.log",
	   settingsfile = "settings.json";

long getId(Twitter4D client)
{
	auto j = client.request("GET", "account/verify_credentials.json", ["include_entities":"false", "skip_status" : "true"]).parseJSON;
	return j.object["id"].integer;
}


string[] parse_text(string s)
{
	dstring[] xs;
	dchar[] x;

	bool escape_flag = false;

	foreach (c; codePoints(s)) {
		if (escape_flag) {
			x ~= c;
			escape_flag = false;
		}
		else if (c == '/') {
			escape_flag = true;
		}
		else if (c.isWhite) {
			 if (x.length > 0) {
				 xs ~= x.dup;
				 x = [];
			 }
		}
		else {
			x ~= c;
		}
	}

	if (x.length > 0) {
		xs ~= x.dup;
	}

	return xs.map!(toUTF8).array;
}

string walkSubstring(string s, ulong len)
{
	ulong l = s.length;
	ulong slen = s.walkLength;
	while (slen > len) {
		l--;
		try {
			slen = s[0..l].walkLength;
		}
		catch (Error o) {
			// pass
		}
	}
	return s[0..l];
}
void update_name(Twitter4D client, JSONValue tweet, string username, string true_name)
{
	auto logf = new FileLogger(logfile);
	string[] terms = parse_text(tweet.object["text"].str);
	if (! terms.canFind("@" ~ username)) {
		return;
	}
	string[] update = terms.find("update_name");

	if (update.length > 1) {
		string new_name = update[1].walkSubstring(20);

		try {
			client.request("POST", "account/update_profile.json", [
					"name":new_name
					]);
			client.request("POST", "statuses/update.json", [
					"status": new_name ~ "も昔は" ~ true_name ~ "でした。"
					]);
		}
		catch (Exception e) {
			client.request("POST", "statuses/update.json", ["status": "[-]update_nameは死にました"]);
			logf.log("[-]" ~ e.msg);	
		}
		logf.log("UPDATED to " ~ new_name);
		logf.log(tweet.toPrettyString);
	}
}

void main(string[] args)
{

	auto help = getopt(args,
			"logfile", &logfile,
			"settingsfile", &settingsfile
		  );

	if (help.helpWanted) {
		defaultGetoptPrinter("update_name", help.options);
	}

	auto logf = new FileLogger(logfile);
	auto settings = readText(settingsfile).parseJSON;
	scope(exit) {
		logf.log("[-]update_name stopped.");
	}

	Twitter4D t4d = new Twitter4D(
			settings["consumer_key"].str,
			settings["consumer_secret"].str,
			settings["access_token"].str,
			settings["access_token_secret"].str,
	);

	long myId = t4d.getId;

	logf.log("[+]update_name launched.");
	try {
		t4d.request("POST", "statuses/update.json", [
				"status": "[+]update_nameがおきました。" ~ Clock.currTime.toISOExtString()
				]);
	}
	catch (Exception e) {
		logf.log("[-]Failed to tweet startup message");
	}

	foreach (tweet; t4d.stream()) {
		if (match(tweet.to!string, regex(r"\{.*\}"))) {
			auto j = parseJSON(tweet.to!string);
			if ("text" in j.object) {
				new Thread(() => (t4d.update_name(j, settings["username"].str, settings["true_name"].str))).start;
			}

		}
	}
}
