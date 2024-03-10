# socketplate

Puts the “fun” in **socket programming**.

## Example: TCP echo server

```d
import socketplate.app;

int main(string[] args) @safe
{
    return runSocketplateApp("Simple echo server", args, delegate(SocketConnection connection)
    {
        ubyte[] buffer = new ubyte[](256);

        while (true) {
            ubyte[] receivedData = connection.receiveSlice(buffer);

            if (receivedData.length == 0)
                return connection.close();

            connection.send(receivedData);
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
