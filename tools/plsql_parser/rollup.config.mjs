// rollup.config.mjs
// Bundlea el checker ANTLR4 PL/SQL en un IIFE compatible con QuickJS.

import resolve  from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import terser   from '@rollup/plugin-terser';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default {
  input: 'src/checker.js',

  output: {
    file:   '../../assets/plsql_checker.js',
    format: 'iife',
    // Nombre del módulo IIFE (no se usa desde fuera, pero rollup lo requiere)
    name:   'PlSqlCheckerBundle',
    // Evita que rollup divida el bundle en chunks
    inlineDynamicImports: true,
  },

  plugins: [
    resolve({
      browser: false,     // QuickJS no es browser ni Node — usar defaults
      preferBuiltins: false,
    }),
    commonjs(),
    terser({
      compress: {
        // Mantener nombres de función para que los mensajes de error sean legibles
        keep_fnames: /^(PlSql|antlr4|Error)/,
        passes: 2,
      },
      mangle: {
        // No manglear propiedades que ANTLR4 accede por nombre de string
        keep_classnames: true,
      },
      format: {
        comments: false,
      },
    }),
  ],

  // Suprimir warnings de dependencias circulares en antlr4
  onwarn(warning, warn) {
    if (warning.code === 'CIRCULAR_DEPENDENCY') return;
    if (warning.code === 'THIS_IS_UNDEFINED')   return;
    warn(warning);
  },
};
