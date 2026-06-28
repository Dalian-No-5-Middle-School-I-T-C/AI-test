import { preferences } from '@kit.ArkData'
import { Conversation, AppSettings, DEFAULT_SETTINGS, ModelType, ReasoningEffort } from '../models/Message'
import { Context } from '@kit.AbilityKit'

const CONVERSATIONS_KEY = 'conversations'
const SETTINGS_KEY = 'settings'

interface SettingsData {
  apiKey?: string
  model?: string
  thinkingEnabled?: boolean
  reasoningEffort?: string
  systemPrompt?: string
}

export class StorageService {
  private preferences: preferences.Preferences | null = null

  async init(context: Context): Promise<void> {
    this.preferences = await preferences.getPreferences(context, 'chat_app_storage')
  }

  async getConversations(): Promise<Conversation[]> {
    if (!this.preferences) return []

    try {
      const data = await this.preferences.get(CONVERSATIONS_KEY, '[]')
      return JSON.parse(data as string) as Conversation[]
    } catch {
      return []
    }
  }

  async saveConversations(conversations: Conversation[]): Promise<void> {
    if (!this.preferences) return

    await this.preferences.put(CONVERSATIONS_KEY, JSON.stringify(conversations))
    await this.preferences.flush()
  }

  async addConversation(conversation: Conversation): Promise<void> {
    const conversations = await this.getConversations()
    conversations.unshift(conversation)
    await this.saveConversations(conversations)
  }

  async updateConversation(conversation: Conversation): Promise<void> {
    const conversations = await this.getConversations()
    const index = conversations.findIndex(c => c.id === conversation.id)
    if (index !== -1) {
      conversations[index] = conversation
      await this.saveConversations(conversations)
    }
  }

  async deleteConversation(conversationId: string): Promise<void> {
    const conversations = await this.getConversations()
    const filtered = conversations.filter(c => c.id !== conversationId)
    await this.saveConversations(filtered)
  }

  async getSettings(): Promise<AppSettings> {
    if (!this.preferences) return DEFAULT_SETTINGS

    try {
      const data = await this.preferences.get(SETTINGS_KEY, '')
      if (!data) return DEFAULT_SETTINGS
      const parsed = JSON.parse(data as string) as SettingsData
      const model: ModelType = (parsed.model === 'deepseek-v4-flash' || parsed.model === 'deepseek-v4-pro') ? parsed.model : DEFAULT_SETTINGS.model
      const reasoningEffort: ReasoningEffort = (parsed.reasoningEffort === 'high' || parsed.reasoningEffort === 'max') ? parsed.reasoningEffort : DEFAULT_SETTINGS.reasoningEffort
      const settings: AppSettings = {
        apiKey: typeof parsed.apiKey === 'string' ? parsed.apiKey : DEFAULT_SETTINGS.apiKey,
        model: model,
        thinkingEnabled: typeof parsed.thinkingEnabled === 'boolean' ? parsed.thinkingEnabled : DEFAULT_SETTINGS.thinkingEnabled,
        reasoningEffort: reasoningEffort,
        systemPrompt: typeof parsed.systemPrompt === 'string' ? parsed.systemPrompt : DEFAULT_SETTINGS.systemPrompt
      }
      return settings
    } catch {
      return DEFAULT_SETTINGS
    }
  }

  async saveSettings(settings: AppSettings): Promise<void> {
    if (!this.preferences) return

    await this.preferences.put(SETTINGS_KEY, JSON.stringify(settings))
    await this.preferences.flush()
  }
}

export const storageService = new StorageService()