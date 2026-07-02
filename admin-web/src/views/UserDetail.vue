<template>
  <div class="user-detail" v-loading="loading">
    <div class="page-header">
      <el-button @click="$router.back()">
        <el-icon><ArrowLeft /></el-icon> 返回用户列表
      </el-button>
    </div>

    <template v-if="data.user">
      <!-- User Info Cards -->
      <el-row :gutter="16" class="info-row">
        <el-col :span="6">
          <el-card class="info-card user-card" shadow="never">
            <div class="user-avatar">
              <el-icon :size="36"><User /></el-icon>
            </div>
            <h3 class="user-name">{{ data.user.username }}</h3>
            <el-tag :type="data.user.is_admin ? 'danger' : 'info'" size="small">
              {{ data.user.is_admin ? '管理员' : '普通用户' }}
            </el-tag>
          </el-card>
        </el-col>
        <el-col :span="6">
          <el-card class="info-card stat-card" shadow="never">
            <div class="stat-label">用户 ID</div>
            <div class="stat-value">{{ data.user.id }}</div>
          </el-card>
        </el-col>
        <el-col :span="6">
          <el-card class="info-card stat-card" shadow="never">
            <div class="stat-label">注册时间</div>
            <div class="stat-value">{{ formatDate(data.user.created_at) }}</div>
          </el-card>
        </el-col>
        <el-col :span="6">
          <el-card class="info-card stat-card" shadow="never">
            <div class="stat-label">文件数量</div>
            <div class="stat-value" style="color: #6366f1">{{ data.files?.length || 0 }}</div>
          </el-card>
        </el-col>
      </el-row>

      <!-- Admin Actions -->
      <el-row :gutter="16" class="action-row" v-if="isAdmin">
        <el-col :span="12">
          <el-card class="action-card" shadow="never">
            <template #header><el-icon><Key /></el-icon> 修改密码</template>
            <div class="action-form">
              <el-input v-model="newPassword" type="password" placeholder="新密码(至少6位)" show-password />
              <el-button type="primary" @click="changePassword" :loading="changingPwd">确认</el-button>
            </div>
          </el-card>
        </el-col>
        <el-col :span="12" v-if="!data.user.is_admin">
          <el-card class="action-card" shadow="never">
            <template #header><el-icon><Edit /></el-icon> 修改用户名</template>
            <div class="action-form">
              <el-input v-model="newUsername" placeholder="新用户名(至少3位)" />
              <el-button type="primary" @click="changeUsername" :loading="changingName">确认</el-button>
            </div>
          </el-card>
        </el-col>
      </el-row>

      <!-- File List -->
      <el-card class="file-card" shadow="never">
        <template #header>📁 文件列表 ({{ data.files?.length || 0 }})</template>
        <el-table :data="data.files" style="width: 100%" max-height="500">
          <el-table-column label="#" width="50">
            <template #default="{ $index }">{{ $index + 1 }}</template>
          </el-table-column>
          <el-table-column label="文件名" min-width="250">
            <template #default="{ row }">
              <div class="file-name-cell">
                <el-image
                  v-if="row.type === 'image' && row.s3Key"
                  :src="`/api/files/${row.id}/thumbnail?token=admin`"
                  fit="cover"
                  class="file-thumb"
                />
                <span>{{ row.name }}</span>
              </div>
            </template>
          </el-table-column>
          <el-table-column label="类型" width="100">
            <template #default="{ row }">
              <el-tag size="small">{{ row.type }}</el-tag>
            </template>
          </el-table-column>
          <el-table-column label="大小" width="100">
            <template #default="{ row }">{{ formatSize(row.fileSize) }}</template>
          </el-table-column>
          <el-table-column label="时间" width="120">
            <template #default="{ row }">{{ formatDate(row.receivedAt) }}</template>
          </el-table-column>
        </el-table>
      </el-card>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { ArrowLeft, User, Key, Edit } from '@element-plus/icons-vue'
import api from '../api'

const route = useRoute()
const loading = ref(false)
const data = ref({ user: null, files: [] })

const newPassword = ref('')
const newUsername = ref('')
const changingPwd = ref(false)
const changingName = ref(false)

const isAdmin = computed(() => {
  const saved = localStorage.getItem('admin_user')
  return saved ? JSON.parse(saved).is_admin : false
})

const loadUser = async () => {
  loading.value = true
  try {
    data.value = await api.get(`/users/${route.params.id}`)
  } catch (error) {
    ElMessage.error('加载用户失败')
  } finally {
    loading.value = false
  }
}

const formatDate = (dateStr) => {
  if (!dateStr) return '-'
  return dateStr.substring(0, 16).replace('T', ' ')
}

const formatSize = (bytes) => {
  if (!bytes) return '-'
  if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + ' MB'
  if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB'
  return bytes + ' B'
}

const changePassword = async () => {
  if (newPassword.value.length < 6) {
    ElMessage.warning('密码至少6位')
    return
  }
  changingPwd.value = true
  try {
    await api.post(`/users/${route.params.id}/change-password`, {
      new_password: newPassword.value,
    })
    ElMessage.success('密码已修改')
    newPassword.value = ''
  } catch (error) {
    ElMessage.error('修改失败')
  } finally {
    changingPwd.value = false
  }
}

const changeUsername = async () => {
  if (newUsername.value.length < 3) {
    ElMessage.warning('用户名至少3位')
    return
  }
  changingName.value = true
  try {
    await api.post(`/users/${route.params.id}/change-username`, {
      new_username: newUsername.value,
    })
    ElMessage.success('用户名已修改')
    await loadUser()
  } catch (error) {
    ElMessage.error(error.response?.data?.detail || '修改失败')
  } finally {
    changingName.value = false
  }
}

onMounted(loadUser)
</script>

<style scoped>
.page-header {
  margin-bottom: 20px;
}

.info-row {
  margin-bottom: 16px;
}

.info-card {
  background: #1f2937;
  border: 1px solid #374151;
  text-align: center;
}

.info-card :deep(.el-card__body) {
  padding: 24px 16px;
}

.user-card .user-avatar {
  width: 72px;
  height: 72px;
  border-radius: 50%;
  background: linear-gradient(135deg, #6366f1, #8b5cf6);
  display: flex;
  align-items: center;
  justify-content: center;
  margin: 0 auto 12px;
  color: #fff;
}

.user-card .user-name {
  font-size: 16px;
  color: #e5e7eb;
  margin-bottom: 8px;
}

.stat-card .stat-label {
  font-size: 12px;
  color: #9ca3af;
  margin-bottom: 8px;
}

.stat-card .stat-value {
  font-size: 24px;
  font-weight: 700;
  color: #e5e7eb;
}

.action-row {
  margin-bottom: 16px;
}

.action-card {
  background: #1f2937;
  border: 1px solid #374151;
}

.action-card :deep(.el-card__header) {
  display: flex;
  align-items: center;
  gap: 6px;
  color: #e5e7eb;
}

.action-form {
  display: flex;
  gap: 8px;
}

.action-form .el-input {
  flex: 1;
}

.file-card {
  background: #1f2937;
  border: 1px solid #374151;
}

.file-card :deep(.el-card__header) {
  color: #e5e7eb;
}

.file-name-cell {
  display: flex;
  align-items: center;
  gap: 8px;
}

.file-thumb {
  width: 36px;
  height: 36px;
  border-radius: 4px;
  flex-shrink: 0;
}
</style>
