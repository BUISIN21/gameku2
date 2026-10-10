import { randomBytes } from 'node:crypto';
import { AccessToken } from 'livekit-server-sdk';

export interface TokenIssuer {
  /** Public WebSocket URL clients connect to. */
  readonly serverUrl: string;
  createJoinToken(params: { roomName: string; identity: string; displayName: string }): Promise<string>;
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
    // and send data (used for chat in Phase 4). No admin, recording or
    // room-management rights.
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

/** Server-chosen identity, so clients cannot impersonate each other. */
export function newGuestIdentity(): string {
  return `guest-${randomBytes(8).toString('hex')}`;
}
