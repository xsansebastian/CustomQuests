# Imports de prueba

En el juego: `/cq` > Plantillas > Importar, pegar el contenido de un archivo.

- `01-todos-los-objetivos.txt` (1 misión, 1312 caracteres): Una sola misión suelta con dos etapas: objeto, matar, matar cualquiera, manual / zona, subzona, ubicación, nivel y jefe.
- `02-diaria.txt` (1 misión, 560 caracteres): Misión repetible diaria (icono de repetible).
- `03-semanal.txt` (1 misión, 564 caracteres): Misión repetible semanal.
- `04-cadena-con-rama.txt` (5 misiones, 3024 caracteres): Cadena de 5 misiones: A > B, y B tiene dos siguientes (C > E y D). Prueba el árbol de Plantillas y que cada una se oculta hasta entregar la anterior.
- `05-cadena-con-repetible.txt` (2 misiones, 1188 caracteres): Dos misiones: una suelta y su siguiente diaria. Ambas deben verse como de campaña.
- `06-solo-novatos.txt` (1 misión, 608 caracteres): Suelta solo para niveles 1-5: debe salir 'bloqueada' si tu personaje es de más nivel.
- `07-solo-veteranos-y-textos.txt` (1 misión, 680 caracteres): Suelta de nivel 100+ (bloqueada por debajo). Mezcla colores y {name}/{class}/{race} en la descripción.
- `08-cadena-en-seccion.txt` (2 misiones, 1280 caracteres): Cadena de 2 misiones dentro de la sección '[Test] Isla perdida': al importar se crea la sección y las dos quedan en ella (una cadena se mueve entera).
- `09-seccion-completa.txt` (5 misiones, 3032 caracteres): Sección '[Test] Rutina' exportada entera: una diaria, una semanal, una cadena de 2 y una suelta. Prueba el export de sección, las cabeceras en Activas y en el rastreador, y que 'Otras misiones' no sale si todas tienen sección.
- `10-seccion-ya-existente.txt` (1 misión, 588 caracteres): Una misión en la sección '[Test] Rutina' (mismo nombre que la 09): importada después de la 09 debe entrar en la sección que ya existe, sin duplicarla. Importada sola, la crea.
- `11-nombre-de-seccion-raro.txt` (1 misión, 620 caracteres): Sección con nombre largo y caracteres especiales (se recorta a 40 y se quitan las barras |): comprueba que la cabecera se ve bien y no rompe el formato.
