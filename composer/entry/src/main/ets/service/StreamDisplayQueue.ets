export type StreamDisplayListener = (content: string, reasoning: string) => void;

export class StreamDisplayQueue {
  private contentTarget: string = '';
  private reasoningTarget: string = '';
  private contentShown: string = '';
  private reasoningShown: string = '';
  private timerId: number = -1;
  private listener: StreamDisplayListener | null = null;

  setListener(listener: StreamDisplayListener): void {
    this.listener = listener;
  }

  reset(): void {
    this.stopTimer();
    this.contentTarget = '';
    this.reasoningTarget = '';
    this.contentShown = '';
    this.reasoningShown = '';
  }

  stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  pushDelta(contentDelta: string, reasoningDelta: string): void {
    if (contentDelta.length > 0) {
      this.contentTarget += contentDelta;
    }
    if (reasoningDelta.length > 0) {
      this.reasoningTarget += reasoningDelta;
    }
    this.ensurePumpRunning();
  }

  syncTargets(content: string, reasoning: string): void {
    this.contentTarget = content;
    this.reasoningTarget = reasoning;
    this.ensurePumpRunning();
  }

  flush(): void {
    this.stopTimer();
    this.contentShown = this.contentTarget;
    this.reasoningShown = this.reasoningTarget;
    this.notifyListener();
  }

  isPending(): boolean {
    return this.reasoningShown.length < this.reasoningTarget.length ||
      this.contentShown.length < this.contentTarget.length;
  }

  private ensurePumpRunning(): void {
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setInterval(() => {
      this.pumpStep();
    }, 16);
  }

  private pumpStep(): void {
    const reasoningRemaining = this.reasoningTarget.length - this.reasoningShown.length;
    const contentRemaining = this.contentTarget.length - this.contentShown.length;
    const totalRemaining = reasoningRemaining + contentRemaining;

    if (totalRemaining <= 0) {
      this.stopTimer();
      return;
    }

    let step = 1;
    if (totalRemaining > 300) {
      step = 12;
    } else if (totalRemaining > 100) {
      step = 6;
    } else if (totalRemaining > 30) {
      step = 3;
    }

    let changed = false;
    if (reasoningRemaining > 0) {
      const take = Math.min(step, reasoningRemaining);
      this.reasoningShown += this.reasoningTarget.substring(
        this.reasoningShown.length,
        this.reasoningShown.length + take,
      );
      changed = true;
    } else if (contentRemaining > 0) {
      const take = Math.min(step, contentRemaining);
      this.contentShown += this.contentTarget.substring(
        this.contentShown.length,
        this.contentShown.length + take,
      );
      changed = true;
    }

    if (changed) {
      this.notifyListener();
    }

    if (!this.isPending()) {
      this.stopTimer();
    }
  }

  private notifyListener(): void {
    if (this.listener !== null) {
      this.listener(this.contentShown, this.reasoningShown);
    }
  }
}
