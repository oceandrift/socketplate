import socketplate.app;

int main(string[] args) @safe
{
    return runSocketplateApp("Socketplate TCP Example", args, delegate(SocketServer server)
    {
        ConnectionHandler handler = delegate(SocketConnection connection)
        {
            ubyte[] b = new ubyte[](256);
            while (true)
            {
                ptrdiff_t received = connection.receive(b);

                if (received == socketERROR)
                    return;

                if (received == 0)
                    return connection.close();

                connection.send(b[0 .. received]);
            }
        };

        server.listenTCP(makeSocketAddress("127.0.0.1", 8080), handler);
        server.listenTCP(makeSocketAddress("[::1]", 8080), handler);
    });
}
