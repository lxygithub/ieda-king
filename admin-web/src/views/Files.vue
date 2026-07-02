<template>
  <div class="files-page">
    <div class="page-header">
      <h2 class="page-title">文件管理</h2>
      <span class="file-count">共 {{ files.length }} 个文件</span>
    </div>

    <!-- Batch actions -->
    <transition name="fade">
      <div v-if="selectedIds.length > 0" class="batch-bar">
        <span>已选 <strong>{{ selectedIds.length }}</strong> 项</span>
        <el-button size="small" @click="clearSelection">取消选择</el-button>
        <el-button type="danger" size="small" @click="batchDelete">
          <el-icon><Delete /></el-icon> 批量删除
        </el-button>
      </div>
    </transition>

    <!-- Table -->
    <el-table
      ref="tableRef"
      :data="files"
      style="width: 100%"
      row-key="id"
      @selection-change="handleSelectionChange"
      v-loading="loading"
    >
      <el-table-column type="selection" width="50" />
      <el-table-column label="#" width="60">
        <template #default="{ $index }">{{ $index + 1 }}</template>
      </el-table-column>
      <el-table-column label="文件名" min-width="280">
        <template #default="{ row }">
          <div class="file-name-cell">
            <el-image
              v-if="row.type === 'image' && row.s3Key"
              :src="`/api/files/${row.id}/thumbnail?token=admin`"
              :preview-src-list="[`/api/files/${row.id}/download?token=admin`]"
              fit="cover"
              class="file-thumb"
            />
            <el-icon v-else class="file-icon" :class="`file-icon-${row.type}`">
              <Document v-if="row.type === 'text'" />
              <VideoPlay v-else-if="row.type === 'video'" />
              <Headset v-else-if="row.type === 'audio'" />
              <Picture v-else-if="row.type === 'image'" />
              <Document v-else />
            </el-icon>
            <span class="file-name">{{ row.name }}</span>
          </div>
        </template>
      </el-table-column>
      <el-table-column label="类型" width="100">
        <template #default="{ row }">
          <el-tag :type="typeTagMap[row.type] || 'info'" size="small">
            {{ row.type }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="大小" width="100">
        <template #default="{ row }">
          {{ formatSize(row.fileSize) }}
        </template>
      </el-table-column>
      <el-table-column label="标签" min-width="150">
        <template #default="{ row }">
          <div v-if="row.tags && row.tags.length" class="tags-cell">
            <el-tag v-for="t in row.tags.slice(0, 3)" :key="t" size="small" type="info">
              {{ t }}
            </el-tag>
            <el-tag v-if="row.tags.length > 3" size="small" type="info">
              +{{ row.tags.length - 3 }}
            </el-tag>
          </div>
          <span v-else class="text-muted">-</span>
        </template>
      </el-table-column>
      <el-table-column label="时间" width="120">
        <template #default="{ row }">
          <span class="text-muted">{{ formatDate(row.receivedAt) }}</span>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="140" fixed="right">
        <template #default="{ row }">
          <div class="actions">
            <el-button
              v-if="row.s3Key && row.type === 'image'"
              size="small"
              circle
              @click="previewFile(row)"
            >
              <el-icon><View /></el-icon>
            </el-button>
            <el-button size="small" circle @click="editFile(row)">
              <el-icon><Edit /></el-icon>
            </el-button>
            <el-popconfirm
              title="确定删除此文件？"
              confirm-button-text="删除"
              cancel-button-text="取消"
              @confirm="deleteFile(row)"
            >
              <template #reference>
                <el-button type="danger" size="small" circle>
                  <el-icon><Delete /></el-icon>
                </el-button>
              </template>
            </el-popconfirm>
          </div>
        </template>
      </el-table-column>
    </el-table>

    <!-- Edit Dialog -->
    <el-dialog v-model="editVisible" title="编辑文件" width="480px">
      <el-form label-position="top">
        <el-form-item label="文件名">
          <el-input v-model="editForm.name" />
        </el-form-item>
        <el-form-item label="标签">
          <div class="edit-tags">
            <el-tag
              v-for="(tag, i) in editForm.tags"
              :key="tag"
              closable
              @close="editForm.tags.splice(i, 1)"
            >
              {{ tag }}
            </el-tag>
          </div>
          <div class="add-tag-row">
            <el-input
              v-model="newTag"
              placeholder="输入标签后回车"
              @keyup.enter="addTag"
            />
            <el-button @click="addTag" :disabled="!newTag.trim()">
              <el-icon><Plus /></el-icon>
            </el-button>
          </div>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="editVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="saveEdit">保存</el-button>
      </template>
    </el-dialog>

    <!-- Preview Dialog -->
    <el-dialog v-model="previewVisible" title="预览" width="80%" top="5vh">
      <el-image
        v-if="previewFileData"
        :src="`/api/files/${previewFileData.id}/download?token=admin`"
        fit="contain"
        style="max-height: 70vh; width: 100%"
      />
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  Delete, View, Edit, Plus, Document, VideoPlay, Headset, Picture
} from '@element-plus/icons-vue'
import api from '../api'

const files = ref([])
const loading = ref(false)
const selectedIds = ref([])

// Edit
const editVisible = ref(false)
const editForm = reactive({ id: '', name: '', tags: [] })
const newTag = ref('')
const saving = ref(false)

// Preview
const previewVisible = ref(false)
const previewFileData = ref(null)

const typeTagMap = {
  image: 'success',
  video: 'warning',
  audio: 'primary',
  text: 'info',
  document: 'info',
}

const loadFiles = async () => {
  loading.value = true
  try {
    files.value = await api.get('/files')
  } catch (error) {
    ElMessage.error('加载文件失败')
  } finally {
    loading.value = false
  }
}

const handleSelectionChange = (rows) => {
  selectedIds.value = rows.map((r) => r.id)
}

const clearSelection = () => {
  selectedIds.value = []
}

const formatSize = (bytes) => {
  if (!bytes) return '-'
  if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + ' MB'
  if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB'
  return bytes + ' B'
}

const formatDate = (dateStr) => {
  if (!dateStr) return '-'
  return dateStr.substring(0, 10)
}

const previewFile = (row) => {
  previewFileData.value = row
  previewVisible.value = true
}

const editFile = (row) => {
  editForm.id = row.id
  editForm.name = row.name
  editForm.tags = [...(row.tags || [])]
  newTag.value = ''
  editVisible.value = true
}

const addTag = () => {
  const tag = newTag.value.trim()
  if (tag && !editForm.tags.includes(tag)) {
    editForm.tags.push(tag)
  }
  newTag.value = ''
}

const saveEdit = async () => {
  saving.value = true
  try {
    await api.put(`/files/${editForm.id}`, {
      name: editForm.name,
      tags: editForm.tags,
    })
    ElMessage.success('保存成功')
    editVisible.value = false
    await loadFiles()
  } catch (error) {
    ElMessage.error('保存失败')
  } finally {
    saving.value = false
  }
}

const deleteFile = async (row) => {
  try {
    await api.delete(`/files/${row.id}`)
    ElMessage.success('删除成功')
    await loadFiles()
  } catch (error) {
    ElMessage.error('删除失败')
  }
}

const batchDelete = async () => {
  try {
    await ElMessageBox.confirm(
      `确定删除选中的 ${selectedIds.value.length} 个文件？`,
      '批量删除',
      { type: 'warning' }
    )
    await api.post('/files/batch-delete', { file_ids: selectedIds.value })
    ElMessage.success('删除成功')
    clearSelection()
    await loadFiles()
  } catch {
    // Cancelled
  }
}

onMounted(loadFiles)
</script>

<style scoped>
.page-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 20px;
}

.page-title {
  font-size: 20px;
  font-weight: 600;
  color: #e5e7eb;
}

.file-count {
  color: #9ca3af;
  font-size: 14px;
}

.batch-bar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  background: #1f2937;
  border: 1px solid #374151;
  border-radius: 8px;
  margin-bottom: 16px;
  color: #e5e7eb;
}

.file-name-cell {
  display: flex;
  align-items: center;
  gap: 10px;
}

.file-thumb {
  width: 40px;
  height: 40px;
  border-radius: 6px;
  flex-shrink: 0;
}

.file-icon {
  width: 40px;
  height: 40px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 16px;
  flex-shrink: 0;
}

.file-icon-image { background: #d1fae5; color: #059669; }
.file-icon-video { background: #fef3c7; color: #d97706; }
.file-icon-audio { background: #e0e7ff; color: #4f46e5; }
.file-icon-text { background: #e0f2fe; color: #0284c7; }

.file-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: #e5e7eb;
}

.tags-cell {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
}

.text-muted {
  color: #6b7280;
}

.actions {
  display: flex;
  gap: 4px;
}

.edit-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-bottom: 8px;
}

.add-tag-row {
  display: flex;
  gap: 8px;
}

.add-tag-row .el-input {
  flex: 1;
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
