<template>
  <div class="users-page">
    <div class="page-header">
      <h2 class="page-title">用户管理</h2>
      <el-button type="primary" @click="showCreateDialog">
        <el-icon><Plus /></el-icon> 新建用户
      </el-button>
    </div>

    <el-table :data="users" style="width: 100%" v-loading="loading">
      <el-table-column label="#" width="60">
        <template #default="{ $index }">{{ $index + 1 }}</template>
      </el-table-column>
      <el-table-column label="用户名" prop="username" />
      <el-table-column label="角色" width="100">
        <template #default="{ row }">
          <el-tag :type="row.is_admin ? 'danger' : 'info'" size="small">
            {{ row.is_admin ? '管理员' : '普通用户' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="注册时间" width="120">
        <template #default="{ row }">
          {{ formatDate(row.created_at) }}
        </template>
      </el-table-column>
      <el-table-column label="操作" width="120" fixed="right">
        <template #default="{ row }">
          <div class="actions">
            <el-button size="small" @click="viewUser(row)">
              <el-icon><View /></el-icon>
            </el-button>
            <el-popconfirm
              v-if="!row.is_admin"
              title="确定删除此用户？"
              @confirm="deleteUser(row)"
            >
              <template #reference>
                <el-button type="danger" size="small">
                  <el-icon><Delete /></el-icon>
                </el-button>
              </template>
            </el-popconfirm>
          </div>
        </template>
      </el-table-column>
    </el-table>

    <!-- Create User Dialog -->
    <el-dialog v-model="createVisible" title="新建用户" width="400px">
      <el-form ref="createFormRef" :model="createForm" :rules="createRules" label-position="top">
        <el-form-item label="用户名" prop="username">
          <el-input v-model="createForm.username" />
        </el-form-item>
        <el-form-item label="密码" prop="password">
          <el-input v-model="createForm.password" type="password" show-password />
        </el-form-item>
        <el-form-item>
          <el-checkbox v-model="createForm.is_admin">管理员</el-checkbox>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="createVisible = false">取消</el-button>
        <el-button type="primary" :loading="creating" @click="createUser">创建</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { Plus, View, Delete } from '@element-plus/icons-vue'
import api from '../api'

const router = useRouter()
const users = ref([])
const loading = ref(false)

// Create
const createVisible = ref(false)
const createFormRef = ref(null)
const creating = ref(false)
const createForm = reactive({ username: '', password: '', is_admin: false })
const createRules = {
  username: [{ required: true, message: '请输入用户名', trigger: 'blur' }],
  password: [
    { required: true, message: '请输入密码', trigger: 'blur' },
    { min: 6, message: '密码至少6位', trigger: 'blur' },
  ],
}

const loadUsers = async () => {
  loading.value = true
  try {
    users.value = await api.get('/users')
  } catch (error) {
    ElMessage.error('加载用户失败')
  } finally {
    loading.value = false
  }
}

const formatDate = (dateStr) => {
  if (!dateStr) return '-'
  return dateStr.substring(0, 10)
}

const showCreateDialog = () => {
  createForm.username = ''
  createForm.password = ''
  createForm.is_admin = false
  createVisible.value = true
}

const createUser = async () => {
  const valid = await createFormRef.value?.validate().catch(() => false)
  if (!valid) return

  creating.value = true
  try {
    await api.post('/users', createForm)
    ElMessage.success('创建成功')
    createVisible.value = false
    await loadUsers()
  } catch (error) {
    ElMessage.error(error.response?.data?.detail || '创建失败')
  } finally {
    creating.value = false
  }
}

const viewUser = (row) => {
  router.push(`/users/${row.id}`)
}

const deleteUser = async (row) => {
  try {
    await api.delete(`/users/${row.id}`)
    ElMessage.success('删除成功')
    await loadUsers()
  } catch (error) {
    ElMessage.error(error.response?.data?.detail || '删除失败')
  }
}

onMounted(loadUsers)
</script>

<style scoped>
.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20px;
}

.page-title {
  font-size: 20px;
  font-weight: 600;
  color: #e5e7eb;
}

.actions {
  display: flex;
  gap: 4px;
}
</style>
