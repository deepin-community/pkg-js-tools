var gulp = require('gulp');
var concat = require('gulp-concat');
gulp.task('def', buildTask);

function buildTask() {
  return gulp.src('src/*.js')
    .pipe(concat('index.js'))
    .pipe(gulp.dest('dist',{ sourcemaps: true }))
}
