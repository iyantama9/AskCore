const MODELS = [
  {
    id: 'mk/sonnet-4.5',
    owned_by: 'Anthropic',
    display_name: 'Sonnet 4.5',
    supports_reasoning: true,
    supports_vision: true,
    supports_image_generation: false,
    supports_browse: true,
    cost_tier: 'premium',
    enabled: true,
  },
  {
    id: 'mk/sonnet-4.5-thinking',
    owned_by: 'Anthropic',
    display_name: 'Sonnet 4.5',
    supports_reasoning: true,
    supports_vision: true,
    supports_image_generation: false,
    supports_browse: true,
    cost_tier: 'premium',
    enabled: true,
  },
  {
    id: 'dh/moonshotai/Kimi-K2.6',
    owned_by: 'Moonshot',
    display_name: 'Kimi K2.6',
    supports_reasoning: false,
    supports_vision: true,
    supports_image_generation: false,
    supports_browse: true,
    cost_tier: 'standard',
    enabled: true,
  },
  {
    id: 'qc/glm-5.2',
    owned_by: 'Zhipu',
    display_name: 'GLM 5.2',
    supports_reasoning: false,
    supports_vision: true,
    supports_image_generation: false,
    supports_browse: true,
    cost_tier: 'standard',
    enabled: true,
  },
  {
    id: 'kc/minimax-m3',
    owned_by: 'MiniMax',
    display_name: 'MiniMax M3',
    supports_reasoning: false,
    supports_vision: false,
    supports_image_generation: false,
    supports_browse: true,
    cost_tier: 'standard',
    enabled: true,
  },
  {
    id: 'qc/qwen-image-2.0',
    owned_by: 'Alibaba',
    display_name: 'Qwen Image 2.0',
    supports_reasoning: false,
    supports_vision: false,
    supports_image_generation: true,
    supports_browse: false,
    cost_tier: 'image',
    enabled: true,
  },
  {
    id: 'qc/qwen-image-2.0-pro',
    owned_by: 'Alibaba',
    display_name: 'Qwen Image Pro',
    supports_reasoning: false,
    supports_vision: false,
    supports_image_generation: true,
    supports_browse: false,
    cost_tier: 'image',
    enabled: true,
  },
];

function listModels() {
  return MODELS.filter((model) => model.enabled);
}

function findModel(id) {
  return MODELS.find((model) => model.id === id && model.enabled) || null;
}

function assertValidModel(id) {
  const model = findModel(id);
  if (!model) {
    const err = new Error('Model is not available');
    err.statusCode = 400;
    err.code = 'MODEL_NOT_AVAILABLE';
    throw err;
  }
  return model;
}

module.exports = { MODELS, listModels, findModel, assertValidModel };
