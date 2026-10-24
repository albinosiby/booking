export class LoginAttempts {
  private readonly attempts = new Map<string, { count: number; expires: number }>();
  constructor(
    private readonly now = Date.now,
    private readonly windowMs = 10 * 60 * 1000,
    private readonly limit = 10,
    private readonly maxKeys = 10000,
  ) {}

  reserve(key: string): boolean {
    const time = this.now();
    for (const [savedKey, value] of this.attempts) {
      if (value.expires <= time) this.attempts.delete(savedKey);
    }
    const value = this.attempts.get(key);
    if (value) {
      if (value.count >= this.limit) return false;
      value.count++;
      return true;
    }
    if (this.attempts.size >= this.maxKeys) return false;
    this.attempts.set(key, { count: 1, expires: time + this.windowMs });
    return true;
  }

  clear(key: string) {
    this.attempts.delete(key);
  }
}

export const loginAttempts = new LoginAttempts();
