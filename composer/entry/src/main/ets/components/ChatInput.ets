@Component
export struct ChatInput {
  @Prop placeholder: string = '输入消息...';
  @Prop inputEnabled: boolean = true;
  @State inputText: string = '';
  onSend?: (text: string) => void;

  build() {
    Row() {
      TextInput({ text: this.inputText, placeholder: this.placeholder })
        .layoutWeight(1)
        .height(40)
        .backgroundColor('#F5F5F5')
        .borderRadius(20)
        .padding({ left: 16, right: 16 })
        .fontSize(15)
        .enabled(this.inputEnabled)
        .onChange((value: string) => {
          this.inputText = value;
        })
        .onSubmit(() => {
          this.handleSend();
        })

      Button('发送')
        .fontSize(14)
        .height(40)
        .padding({ left: 16, right: 16 })
        .margin({ left: 8 })
        .borderRadius(20)
        .backgroundColor(this.inputText.trim().length > 0 && this.inputEnabled ? '#4A90D9' : '#CCCCCC')
        .enabled(this.inputText.trim().length > 0 && this.inputEnabled)
        .onClick(() => {
          this.handleSend();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#FFFFFF')
  }

  private handleSend(): void {
    let text = this.inputText.trim();
    if (text.length > 0 && this.onSend) {
      this.onSend(text);
      this.inputText = '';
    }
  }

  clearInput(): void {
    this.inputText = '';
  }
}
