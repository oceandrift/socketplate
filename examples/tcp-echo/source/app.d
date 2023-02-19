import socketplate.app;

int main(string[] args) @safe
{
    return runSocketplateAppTCP("Socketplate TCP Echo Example", args, delegate(SocketConnection connection)
    {
        ubyte[] b = new ubyte[](256);

        while (true)
        {
            ubyte[] received = connection.receiveSlice(b);

            if (received.length == 0)
                return connection.close();

            connection.send(received);
        }
    });
}
