<template>
  <div class="login-container">
    <div class="login-card">
      <div class="login-logo">
        <span>💡</span>
      </div>
      <h1 class="login-title">点子王</h1>
      <p class="login-subtitle">管理后台</p>

      <el-form ref="formRef" :model="form" :rules="rules" @submit.prevent="handleLogin">
        <el-form-item prop="username">
          <el-input
            v-model="form.username"
            placeholder="用户名"
            prefix-icon="User"
            size="large"
          />
        </el-form-item>
        <el-form-item prop="password">
          <el-input
            v-model="form.password"
            type="password"
            placeholder="密码"
            prefix-icon="Lock"
            size="large"
            show-password
          />
        </el-form-item>
        <el-form-item>
          <el-button
            type="primary"
            size="large"
            :loading="loading"
            class="login-btn"
            @click="handleLogin"
          >
            登录
          </el-button>
        </el-form-item>
      </el-form>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import api from '../api'

const router = useRouter()
const formRef = ref(null)
const loading = ref(false)

const form = reactive({
  username: '',
  password: '',
})

const rules = {
  username: [{ required: true, message: '请输入用户名', trigger: 'blur' }],
  password: [{ required: true, message: '请输入密码', trigger: 'blur' }],
}

const handleLogin = async () => {
  const valid = await formRef.value?.validate().catch(() => false)
  if (!valid) return

  loading.value = true
  try {
    const res = await api.post('/auth/login', form)
    if (res.success) {
      localStorage.setItem('admin_user', JSON.stringify({
        id: res.user_id,
        username: res.username,
        is_admin: res.is_admin,
      }))
      ElMessage.success('登录成功')
      router.push('/')
    } else {
      ElMessage.error(res.error || '登录失败')
    }
  } catch (error) {
    ElMessage.error('登录失败')
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.login-container {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #1a1a2e;
}

.login-card {
  width: 400px;
  padding: 40px;
  background: #1f2937;
  border-radius: 16px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
  border: 1px solid #374151;
}

.login-logo {
  width: 80px;
  height: 80px;
  background: linear-gradient(135deg, #6366f1, #8b5cf6);
  border-radius: 20px;
  margin: 0 auto 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 36px;
}

.login-title {
  font-size: 24px;
  font-weight: 700;
  color: #e5e7eb;
  text-align: center;
  margin-bottom: 4px;
}

.login-subtitle {
  color: #9ca3af;
  font-size: 14px;
  text-align: center;
  margin-bottom: 32px;
}

.login-btn {
  width: 100%;
}
</style>
