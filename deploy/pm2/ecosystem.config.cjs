module.exports = {
  apps: [
    {
      name: 'ttaxi-api-staging',
      cwd: '/srv/ttaxi/current/backend',
      script: 'src/server.js',
      exec_mode: 'fork',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '512M',
      kill_timeout: 10000,
      time: true,
      error_file: '/var/log/ttaxi/api-error.log',
      out_file: '/var/log/ttaxi/api-out.log',
      env: {
        NODE_ENV: 'staging',
        TZ: 'Asia/Bangkok',
      },
      env_staging: {
        NODE_ENV: 'staging',
        TZ: 'Asia/Bangkok',
      },
      env_production: {
        NODE_ENV: 'production',
        TZ: 'Asia/Bangkok',
      },
    },
  ],
};
