import { createRouter, createWebHistory } from 'vue-router'

const routes = [
  {
    path: '/login',
    name: 'Login',
    component: () => import('../views/Login.vue'),
    meta: { requiresAuth: false },
  },
  {
    path: '/',
    component: () => import('../views/Layout.vue'),
    meta: { requiresAuth: true },
    children: [
      {
        path: '',
        redirect: { name: 'Dashboard' },
      },
      {
        path: 'dashboard',
        name: 'Dashboard',
        component: () => import('../views/Dashboard.vue'),
      },
      {
        path: 'files',
        name: 'Files',
        component: () => import('../views/Files.vue'),
      },
      {
        path: 'users',
        name: 'Users',
        component: () => import('../views/Users.vue'),
      },
      {
        path: 'users/:id',
        name: 'UserDetail',
        component: () => import('../views/UserDetail.vue'),
      },
    ],
  },
]

const router = createRouter({
  history: createWebHistory('/admin-new/'),
  routes,
})

// Auth guard
router.beforeEach((to, from, next) => {
  const isAuthenticated = localStorage.getItem('admin_user')

  if (to.meta.requiresAuth && !isAuthenticated) {
    next({ name: 'Login' })
  } else if (to.name === 'Login' && isAuthenticated) {
    next({ name: 'Dashboard' })
  } else {
    next()
  }
})

export default router
