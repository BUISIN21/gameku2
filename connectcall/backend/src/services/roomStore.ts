import { randomInt } from 'node:crypto';

/**
 * Room codes use an alphabet without look-alike characters (0/o, 1/l/i) so they
 * can be read aloud or typed. 12 characters from 31 symbols ≈ 59 bits of
 * entropy, which makes guessing an active code impractical, especially with
 * the join endpoint's rate limit.
 */
const ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789';
const CODE_GROUPS = 3;
const GROUP_LENGTH = 4;

export const ROOM_CODE_PATTERN = /^[a-hjkmnp-z2-9]{4}-[a-hjkmnp-z2-9]{4}-[a-hjkmnp-z2-9]{4}$/;

export interface RoomRecord {
  code: string;
  createdAt: number;
  expiresAt: number;
  createdByName: string;
}

export function generateRoomCode(): string {
  const groups: string[] = [];
  for (let g = 0; g < CODE_GROUPS; g++) {
    let group = '';
    for (let i = 0; i < GROUP_LENGTH; i++) group += ALPHABET[randomInt(ALPHABET.length)];
    groups.push(group);
  }
  return groups.join('-');
}

/** Normalises user input such as " ABCD efgh-JKMN " to "abcd-efgh-jkmn". */
export function normalizeRoomCode(input: string): string | null {
  const compact = input.toLowerCase().replace(/[\s-]/g, '');
  if (compact.length !== CODE_GROUPS * GROUP_LENGTH) return null;
  const code = compact.match(/.{4}/g)!.join('-');
  return ROOM_CODE_PATTERN.test(code) ? code : null;
}

/**
 * Phase 2 room registry. It lives in process memory, so rooms are forgotten on
 * restart and it only works with a single backend instance. Phase 3 replaces
 * it with Firestore.
 */
export class InMemoryRoomStore {
  private readonly rooms = new Map<string, RoomRecord>();

  constructor(
    private readonly ttlMs: number,
    private readonly now: () => number = Date.now,
    private readonly maxRooms = 10_000,
  ) {}

  create(createdByName: string): RoomRecord {
    this.sweep();
    if (this.rooms.size >= this.maxRooms) throw new RoomLimitError();
    let code = generateRoomCode();
    while (this.rooms.has(code)) code = generateRoomCode();
    const createdAt = this.now();
    const record: RoomRecord = { code, createdAt, expiresAt: createdAt + this.ttlMs, createdByName };
    this.rooms.set(code, record);
    return record;
  }

  /** Returns the room if it exists and has not expired. */
  get(code: string): RoomRecord | undefined {
    const record = this.rooms.get(code);
    if (!record) return undefined;
    if (record.expiresAt <= this.now()) {
      this.rooms.delete(code);
      return undefined;
    }
    return record;
  }

  private sweep(): void {
    const now = this.now();
    for (const [code, record] of this.rooms) {
      if (record.expiresAt <= now) this.rooms.delete(code);
    }
  }
}

export class RoomLimitError extends Error {
  constructor() {
    super('Room limit reached');
  }
}
