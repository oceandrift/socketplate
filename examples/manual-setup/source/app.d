import socketplate.app;

int main(string[] args) @safe
{
    return runSocketplateApp("Socketplate TCP Example", args, delegate(SocketServer server) {
        ConnectionHandler handler = delegate(SocketConnection connection) {
            ubyte[] b = new ubyte[](1);
            while (true)
            {
                ptrdiff_t received = connection.receive(b);
                if (received == 0)
                    return connection.close();
                connection.send(b);
            }
        };

        server.listenTCP(makeSocketAddress("127.0.0.1", 8080), handler);
        server.listenTCP(makeSocketAddress("[::1]", 8080), handler);
    });
}
