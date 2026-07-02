<template>
  <el-container class="layout-container">
    <!-- Sidebar -->
    <el-aside :width="isCollapse ? '64px' : '220px'" class="layout-aside">
      <div class="aside-header">
        <span class="logo">💡</span>
        <span v-if="!isCollapse" class="logo-text">点子王</span>
      </div>
      <el-menu
        :default-active="activeMenu"
        :collapse="isCollapse"
        router
        class="aside-menu"
      >
        <el-menu-item index="/dashboard">
          <el-icon><DataBoard /></el-icon>
          <template #title>概览</template>
        </el-menu-item>
        <el-menu-item index="/files">
          <el-icon><FolderOpened /></el-icon>
          <template #title>文件管理</template>
        </el-menu-item>
        <el-menu-item v-if="user?.is_admin" index="/users">
          <el-icon><User /></el-icon>
          <template #title>用户管理</template>
        </el-menu-item>
      </el-menu>
    </el-aside>

    <!-- Main -->
    <el-container>
      <el-header class="layout-header">
        <div class="header-left">
          <el-icon class="collapse-btn" @click="isCollapse = !isCollapse">
            <Fold v-if="!isCollapse" />
            <Expand v-else />
          </el-icon>
        </div>
        <div class="header-right">
          <el-dropdown trigger="click" @command="handleCommand">
            <span class="user-info">
              <el-icon><UserFilled /></el-icon>
              {{ user?.username }}
              <el-icon class="el-icon--right"><ArrowDown /></el-icon>
            </span>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item command="logout">
                  <el-icon><SwitchButton /></el-icon>
                  退出登录
                </el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
        </div>
      </el-header>

      <el-main class="layout-main">
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessageBox } from 'element-plus'
import {
  DataBoard, FolderOpened, User, Fold, Expand,
  UserFilled, ArrowDown, SwitchButton
} from '@element-plus/icons-vue'
import api from '../api'

const route = useRoute()
const router = useRouter()

const isCollapse = ref(false)
const user = ref(null)

const activeMenu = computed(() => route.path)

onMounted(() => {
  const saved = localStorage.getItem('admin_user')
  if (saved) {
    user.value = JSON.parse(saved)
  }
})

const handleCommand = async (command) => {
  if (command === 'logout') {
    try {
      await ElMessageBox.confirm('确定退出登录？', '提示', {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: 'warning',
      })
      await api.post('/auth/logout')
      localStorage.removeItem('admin_user')
      router.push('/login')
    } catch {
      // Cancelled
    }
  }
}
</script>

<style scoped>
.layout-container {
  min-height: 100vh;
}

.layout-aside {
  background: #1f2937;
  transition: width 0.3s;
  overflow: hidden;
}

.aside-header {
  height: 60px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  border-bottom: 1px solid #374151;
}

.logo {
  font-size: 24px;
}

.logo-text {
  font-size: 16px;
  font-weight: 700;
  color: #e5e7eb;
}

.aside-menu {
  border-right: none;
  background: transparent;
}

.aside-menu:not(.el-menu--collapse) {
  width: 220px;
}

.layout-header {
  background: #1f2937;
  border-bottom: 1px solid #374151;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;
}

.header-left {
  display: flex;
  align-items: center;
}

.collapse-btn {
  font-size: 20px;
  color: #e5e7eb;
  cursor: pointer;
}

.collapse-btn:hover {
  color: #6366f1;
}

.header-right {
  display: flex;
  align-items: center;
}

.user-info {
  display: flex;
  align-items: center;
  gap: 6px;
  color: #e5e7eb;
  cursor: pointer;
}

.user-info:hover {
  color: #6366f1;
}

.layout-main {
  background: #111827;
  padding: 20px;
}
</style>
