var gulp = require('gulp');
var concat = require('gulp-concat');

function buildTask() {
  return gulp.src(['src/index.js'])
    .pipe(concat('index.js'))
    .pipe(gulp.dest('dist'))
}

exports.build = gulp.series(buildTask);
