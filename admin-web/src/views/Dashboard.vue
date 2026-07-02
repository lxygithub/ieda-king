<template>
  <div class="dashboard">
    <h2 class="page-title">概览</h2>

    <el-row :gutter="20">
      <el-col :span="8">
        <el-card class="stat-card" shadow="hover">
          <div class="stat-icon" style="background: linear-gradient(135deg, #6366f1, #8b5cf6)">
            <el-icon :size="28"><User /></el-icon>
          </div>
          <div class="stat-info">
            <div class="stat-value">{{ data.user_count ?? '-' }}</div>
            <div class="stat-label">用户总数</div>
          </div>
        </el-card>
      </el-col>
      <el-col :span="8">
        <el-card class="stat-card" shadow="hover">
          <div class="stat-icon" style="background: linear-gradient(135deg, #10b981, #059669)">
            <el-icon :size="28"><FolderOpened /></el-icon>
          </div>
          <div class="stat-info">
            <div class="stat-value">{{ data.file_count ?? '-' }}</div>
            <div class="stat-label">文件总数</div>
          </div>
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { User, FolderOpened } from '@element-plus/icons-vue'
import api from '../api'

const data = ref({})

onMounted(async () => {
  try {
    data.value = await api.get('/dashboard')
  } catch (error) {
    console.error('Failed to load dashboard:', error)
  }
})
</script>

<style scoped>
.page-title {
  font-size: 20px;
  font-weight: 600;
  color: #e5e7eb;
  margin-bottom: 24px;
}

.stat-card {
  background: #1f2937;
  border: 1px solid #374151;
}

.stat-card :deep(.el-card__body) {
  display: flex;
  align-items: center;
  gap: 20px;
  padding: 24px;
}

.stat-icon {
  width: 56px;
  height: 56px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  flex-shrink: 0;
}

.stat-value {
  font-size: 28px;
  font-weight: 700;
  color: #e5e7eb;
}

.stat-label {
  font-size: 13px;
  color: #9ca3af;
  margin-top: 4px;
}
</style>
