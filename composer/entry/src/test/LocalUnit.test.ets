import { describe, it, expect } from '@ohos/hypium';
import { ToolService } from '../main/ets/services/ToolService';

export default function localUnitTest() {
  describe('ToolServiceTest', () => {
    it('getToolDefinitions_shouldIncludeGetCurrentTime', 0, () => {
      let tools = ToolService.getToolDefinitions();
      expect(tools.length).assertEqual(1);
      expect(tools[0].function.name).assertEqual('get_current_time');
    });

    it('executeTool_getCurrentTime_shouldReturnValidJson', 0, () => {
      let result = ToolService.executeTool('get_current_time', '{}');
      expect(result.length).assertLarger(0);
      let parsed = JSON.parse(result) as Record<string, Object>;
      expect(parsed['time'] !== undefined).assertTrue();
      expect(parsed['timestamp'] !== undefined).assertTrue();
    });

    it('executeTool_unknownTool_shouldReturnError', 0, () => {
      let result = ToolService.executeTool('unknown_tool', '{}');
      let parsed = JSON.parse(result) as Record<string, Object>;
      expect((parsed['error'] as string).includes('Unknown tool')).assertTrue();
    });
  });
}
