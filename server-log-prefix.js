'use strict';

// Preloaded via `node -r` so EngineFS logs get a [server] prefix without
// patching vendor server.js. Prefixes every line of stdout/stderr.

const TAG = '[server] ';

function prefixStream(stream) {
    const origWrite = stream.write.bind(stream);
    let leftover = '';

    stream.write = (chunk, encoding, cb) => {
        if (typeof encoding === 'function') {
            cb = encoding;
            encoding = 'utf8';
        }

        const text = leftover + (typeof chunk === 'string'
            ? chunk
            : chunk.toString(encoding || 'utf8'));
        const lines = text.split('\n');
        leftover = lines.pop();

        if (!lines.length) {
            if (typeof cb === 'function') cb();
            return true;
        }

        return origWrite(lines.map((line) => TAG + line).join('\n') + '\n', encoding, cb);
    };

    process.on('exit', () => {
        if (leftover) {
            origWrite(TAG + leftover + '\n');
            leftover = '';
        }
    });
}

prefixStream(process.stdout);
prefixStream(process.stderr);
