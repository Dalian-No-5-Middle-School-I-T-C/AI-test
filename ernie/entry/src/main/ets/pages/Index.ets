import { router } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  aboutToAppear() {
    router.replaceUrl({ url: 'pages/ChatPage' });
  }

  build() {
    Blank();
  }
}

export default Index;
