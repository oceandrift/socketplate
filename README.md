# socketplate

Puts the “fun” in **socket programming**.

## TCP echo server example

```d
import socketplate.app;

int main(string[] args) @safe {
    return runSocketplateAppTCP("Simple echo server", args, delegate(SocketConnection connection) {
        ubyte[] buffer = new ubyte[](1);

        while (true) {
            ptrdiff_t received = connection.receive(buffer);

            if (received <= 0)
                return connection.close();

            connection.send(buffer);
        }
    });
}
```

```sh
# listen on IPv4 localhost TCP port 8080
./tcp-echo -S 127.0.0.1:8080

# how about IPv6 as well?
./tcp-echo -S 127.0.0.1:8080 -S [::1]:8080

# there’s more:
./tcp-echo --help
```

## Manual

Visit the modules’ doc comments for further information.
