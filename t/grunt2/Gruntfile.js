module.exports = function(grunt) {

  grunt.initConfig({
    concat: {
      dist: {
        src: ['src/*.js'],
        dest: 'dist/index.js'
      }
    }
  });

  grunt.loadNpmTasks('grunt-contrib-concat');
  grunt.registerTask('default', ['concat']);
};
