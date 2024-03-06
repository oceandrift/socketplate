/++
    Parsing of all kind of socket addresses

    ## Currently supported

    $(LIST
        * Unix Domain Socket path (e.g. `/var/run/myapp.sock`)
        * IPv4 address (e.g. `192.168.0.1`)
        * IPv4 address with port (e.g. `192.168.0.1:1234`)
        * IPv6 address (e.g. `[2001:0db8::1]`)
        * IPv6 address with port (e.g. `[2001:0db8::1]:1234`)
    )

    ## Rules

    $(LIST
        * Unix Domain socket paths MUST be absolute (i.e. start with `/`) to prevent ambiguity.
        * IPv4 resp. IPv6 addresses are separated from their (optional) accompanying port number by `:`.
        * IPv6 addresses MUST be encapsulated in square brackets (`[…]`). (This prevents ambiguity with regard to the address/port separator `:`.)
    )

    ## Idea

    Socket addresses are intended to provide a concise way to describe the “address” of network socket.

    The original use case was to provide a simple way to describe listening sockets in a uniform way.
    For a command line interface there should only be a single `--socket=<address>` parameter,
    regardless of whether the specified address is IPv4 or IPv6 – or even a Unix Domain Socket path.

    ### Relation to URIs

    While similarly looking, socket addresses neither are URIs nor to be considered a part/subset of them.
    
    For example, in comparison to URIs there’s no protocol scheme or path.
    Also there are no domain names in socket addresses (thus no DNS resolution necessary or provided).
 +/
module socketplate.address;

import std.ascii : isDigit;
import std.conv : to;
import std.string : indexOf;

@safe pure nothrow:

///
struct SocketAddress {
    ///
    Type type = Type.invalid;

    ///
    string address = null;

    ///
    int port = int.min;

    ///
    enum Type {
        ///
        invalid = -1,

        /// Unix Domain Socket
        unixDomain = 0,

        /// Internet Protocal Version 4 (IPv4) address
        ipv4,

        /// Internet Protocal Version 6 (IPv6) address
        ipv6,
    }
}

/++
    Socket address triage and parsing function

    Determines the type (IPv4, IPv6, Unix Domain Socket etc.) of a socket
    and parses it according to the rules mentioned in this module’s description.

    $(WARNING
        Does not actually validate addresses (or paths).
    )

    Returns:
        true = on success, or
        false = on error (invalid input)
 +/
bool parseSocketAddress(string input, out SocketAddress result) {
    // Unix Domain Socket
    if (input[0] == '/') {
        return parseUnixDomain(input, result);
    }

    // IPv6
    if (input[0] == '[') {
        return parseIPv6(input, result);
    }

    // IPv4

    // basic garbage detection
    foreach (ref c; input) {
        if ((!c.isDigit) && (c != '.') && (c != ':')) {
            return false;
        }
    }

    return parseIPv4(input, result);
}

///
unittest {
    SocketAddress sockAddr;

    assert(parseSocketAddress("127.0.0.1:8080", sockAddr));
    assert(sockAddr == SocketAddress(SocketAddress.Type.ipv4, "127.0.0.1", 8080));

    assert(parseSocketAddress("127.0.0.1", sockAddr));
    assert(sockAddr == SocketAddress(SocketAddress.Type.ipv4, "127.0.0.1", int.min));

    assert(parseSocketAddress("[::]:993", sockAddr));
    assert(sockAddr == SocketAddress(SocketAddress.Type.ipv6, "::", 993));

    assert(parseSocketAddress("[::1]", sockAddr));
    assert(sockAddr == SocketAddress(SocketAddress.Type.ipv6, "::1", int.min));

    assert(parseSocketAddress("/var/run/myapp.sock", sockAddr));
    assert(sockAddr == SocketAddress(SocketAddress.Type.unixDomain, "/var/run/myapp.sock", int.min));

    assert(!parseSocketAddress("myapp.sock", sockAddr));
    assert(!parseSocketAddress("::1", sockAddr));
    assert(!parseSocketAddress("http://127.0.0.1", sockAddr));
}

///
SocketAddress makeSocketAddress(string address, ushort port) {
    assert(address.length >= 4, "Invalid IP address");

    // IPv6?
    if (address[0] == '[') {
        return SocketAddress(
            SocketAddress.Type.ipv6,
            address[1 .. ($ - 1)],
            port
        );
    }  // IPv4?
    else if (address[0].isDigit) {
        return SocketAddress(
            SocketAddress.Type.ipv4,
            address,
            port
        );
    }

    assert(false, "Invalid IP address");
}

///
SocketAddress makeSocketAddress(string unixDomainSocketPath) {
    return SocketAddress(SocketAddress.Type.unixDomain, unixDomainSocketPath);
}

private:

bool parseUnixDomain(string input, out SocketAddress result) @nogc {
    result = SocketAddress(SocketAddress.Type.unixDomain, input);
    return true;
}

bool parseIPv6(string input, out SocketAddress result) {
    immutable ptrdiff_t idxEndOfAddress = input.indexOf(']');
    if (idxEndOfAddress < 0) {
        return false;
    }

    int port = int.min;

    if ((idxEndOfAddress + 1) < input.length) {
        string portStr = input[(idxEndOfAddress + 1) .. $];
        if (portStr[0] != ':') {
            return false;
        }

        portStr = portStr[1 .. $];
        immutable portValid = parsePort(portStr, port);
        if (!portValid) {
            return false;
        }
    }

    immutable string address = input[1 .. idxEndOfAddress];

    result = SocketAddress(SocketAddress.Type.ipv6, address, port);
    return true;
}

bool parseIPv4(string input, out SocketAddress result) {
    ptrdiff_t idxPortSep = input.indexOf(':');

    if (idxPortSep == 0) {
        return false;
    }

    int port = int.min;

    if (idxPortSep > 0) {
        immutable portValid = parsePort(input[(idxPortSep + 1) .. $], port);
        if (!portValid) {
            return false;
        }
    }

    immutable string address = (idxPortSep > 0) ? input[0 .. idxPortSep] : input;

    result = SocketAddress(SocketAddress.Type.ipv4, address, port);
    return true;
}

bool parsePort(scope string input, out int result) {
    try {
        result = input.to!ushort;
    } catch (Exception) {
        return false;
    }

    return true;
}
