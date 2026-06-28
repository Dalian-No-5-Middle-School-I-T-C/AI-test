import { describe, it, expect } from '@ohos/hypium';
import { ToolService } from '../../../main/ets/services/ToolService';

export default function toolServiceTest() {
  describe('ToolServiceOhosTest', () => {
    it('shouldDefineGetCurrentTimeTool', 0, () => {
      let tools = ToolService.getToolDefinitions();
      expect(tools.length).assertEqual(1);
      expect(tools[0].function.name).assertEqual('get_current_time');
    });

    it('shouldExecuteGetCurrentTime', 0, () => {
      let result = ToolService.executeTool('get_current_time', '{}');
      expect(result.includes('timestamp')).assertTrue();
    });
  });
}
