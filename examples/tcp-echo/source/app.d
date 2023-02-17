import socketplate.app;

int main(string[] args) @safe
{
    return runSocketplateAppTCP("Socketplate TCP Echo Example", args, delegate(SocketConnection connection)
    {
        ubyte[] b = new ubyte[](1);

        while (true)
        {
            ptrdiff_t received = connection.receive(b);

            if (received <= 0)
                return connection.close();

            connection.send(b);
        }
    });
}
