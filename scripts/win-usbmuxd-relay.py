"""TCP relay: WSL host address -> Apple Mobile Device service on Windows loopback (usbmuxd protocol, port 27015).

Lets libimobiledevice/xtool inside WSL use Windows' Apple USB stack via USBMUXD_SOCKET_ADDRESS=<host>:27015.
"""
import asyncio
import sys

LISTEN_HOST = sys.argv[1] if len(sys.argv) > 1 else "172.19.96.1"
PORT = 27015


async def pipe(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle(client_reader, client_writer):
    try:
        up_reader, up_writer = await asyncio.open_connection("127.0.0.1", PORT)
    except OSError as error:
        print(f"upstream connect failed: {error}", flush=True)
        client_writer.close()
        return
    await asyncio.gather(pipe(client_reader, up_writer), pipe(up_reader, client_writer))


async def main():
    server = await asyncio.start_server(handle, LISTEN_HOST, PORT)
    print(f"relay listening on {LISTEN_HOST}:{PORT} -> 127.0.0.1:{PORT}", flush=True)
    async with server:
        await server.serve_forever()


asyncio.run(main())
