export class SSEParser {
  private buffer: string = '';

  feed(chunk: string, onEvent: (data: string) => void): void {
    this.buffer += chunk;
    const lines: string[] = this.buffer.split('\n');
    this.buffer = lines[lines.length - 1];
    for (let i = 0; i < lines.length - 1; i++) {
      const line: string = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      if (line.startsWith('data:')) {
        const data: string = line.substring(5).trim();
        if (data.length > 0) {
          onEvent(data);
        }
      }
    }
  }

  reset(): void {
    this.buffer = '';
  }
}
