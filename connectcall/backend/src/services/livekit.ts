import { AccessToken, RoomServiceClient } from 'livekit-server-sdk';

export interface TokenIssuer {
  /** Public WebSocket URL clients connect to. */
  readonly serverUrl: string;
  createJoinToken(params: { roomName: string; identity: string; displayName: string }): Promise<string>;
}

/** Server-side LiveKit actions the room owner can trigger through the API. */
export interface LiveKitAdmin {
  removeParticipant(roomName: string, identity: string): Promise<void>;
  /** Disconnects everyone currently in the call. */
  endCall(roomName: string): Promise<void>;
}

export class LiveKitTokenIssuer implements TokenIssuer {
  constructor(
    readonly serverUrl: string,
    private readonly apiKey: string,
    private readonly apiSecret: string,
    private readonly ttlSeconds: number,
  ) {}

  async createJoinToken(params: { roomName: string; identity: string; displayName: string }): Promise<string> {
    const token = new AccessToken(this.apiKey, this.apiSecret, {
      identity: params.identity,
      name: params.displayName,
      ttl: this.ttlSeconds,
    });
    // Least privilege: join exactly one room, publish camera/mic, subscribe,
    // and send data (used for chat signalling). No admin, recording or
    // room-management rights; owner actions go through this API instead.
    token.addGrant({
      room: params.roomName,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
      canUpdateOwnMetadata: false,
    });
    return token.toJwt();
  }
}

export class LiveKitRoomAdmin implements LiveKitAdmin {
  private readonly client: RoomServiceClient;

  constructor(serverUrl: string, apiKey: string, apiSecret: string) {
    // The REST API lives on the same host as the WebSocket endpoint.
    this.client = new RoomServiceClient(serverUrl.replace(/^ws/, 'http'), apiKey, apiSecret);
  }

  async removeParticipant(roomName: string, identity: string): Promise<void> {
    try {
      await this.client.removeParticipant(roomName, identity);
    } catch (err) {
      if (!isNotFound(err)) throw err; // not in the call right now: nothing to do
    }
  }

  async endCall(roomName: string): Promise<void> {
    try {
      await this.client.deleteRoom(roomName);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }
}

function isNotFound(err: unknown): boolean {
  const e = err as { status?: number; code?: string; message?: string };
  return e?.status === 404 || e?.code === 'not_found' || /not.?found/i.test(e?.message ?? '');
}
