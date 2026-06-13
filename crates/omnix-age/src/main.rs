//! omnix-age: age encryption keyed off SSH identities, the omnix-owned
//! replacement for the `rage` calls in the deploy/terraform tooling.
//!
//! - `encrypt` takes one or more `ssh-ed25519`/`ssh-rsa` recipient public keys
//!   (the role recipients resolved from `keys.nix`) and writes an age file.
//! - `decrypt` takes an SSH identity file (locally the operator key, on-host the
//!   `/etc/ssh/ssh_host_ed25519_key`) and recovers the plaintext.

use std::fs::File;
use std::io::{Read, Write};
use std::str::FromStr;

use anyhow::{anyhow, bail, Context, Result};
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "omnix-age", version, about = "age encryption with SSH keys for omnix")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Encrypt INPUT to one or more SSH recipient public keys.
    Encrypt {
        /// Recipient SSH public key (repeatable), e.g. "ssh-ed25519 AAAA...".
        #[arg(short, long = "recipient", required = true)]
        recipients: Vec<String>,
        /// Output path ("-" for stdout).
        #[arg(short, long, default_value = "-")]
        output: String,
        /// Input path ("-" for stdin).
        #[arg(default_value = "-")]
        input: String,
    },
    /// Decrypt INPUT with an SSH identity file.
    Decrypt {
        /// SSH private key identity file.
        #[arg(short, long)]
        identity: String,
        /// Output path ("-" for stdout).
        #[arg(short, long, default_value = "-")]
        output: String,
        /// Input path ("-" for stdin).
        #[arg(default_value = "-")]
        input: String,
    },
}

fn read_all(path: &str) -> Result<Vec<u8>> {
    if path == "-" {
        let mut buf = Vec::new();
        std::io::stdin()
            .read_to_end(&mut buf)
            .context("reading stdin")?;
        Ok(buf)
    } else {
        std::fs::read(path).with_context(|| format!("reading {path}"))
    }
}

fn write_all(path: &str, data: &[u8]) -> Result<()> {
    if path == "-" {
        std::io::stdout().write_all(data).context("writing stdout")
    } else {
        let mut f = File::create(path).with_context(|| format!("creating {path}"))?;
        f.write_all(data).with_context(|| format!("writing {path}"))
    }
}

fn encrypt(recipients: &[String], input: &str, output: &str) -> Result<()> {
    let recips: Vec<Box<dyn age::Recipient + Send>> = recipients
        .iter()
        .map(|r| {
            age::ssh::Recipient::from_str(r)
                .map(|x| Box::new(x) as Box<dyn age::Recipient + Send>)
                .map_err(|e| anyhow!("invalid recipient {r:?}: {e:?}"))
        })
        .collect::<Result<_>>()?;

    let encryptor =
        age::Encryptor::with_recipients(recips).context("at least one recipient is required")?;

    let plaintext = read_all(input)?;
    let mut encrypted = Vec::new();
    let mut writer = encryptor
        .wrap_output(&mut encrypted)
        .context("starting encryption")?;
    writer.write_all(&plaintext).context("encrypting")?;
    writer.finish().context("finishing encryption")?;

    write_all(output, &encrypted)
}

fn decrypt(identity: &str, input: &str, output: &str) -> Result<()> {
    let id_text =
        std::fs::read_to_string(identity).with_context(|| format!("reading identity {identity}"))?;
    let id = age::ssh::Identity::from_buffer(id_text.as_bytes(), Some(identity.to_string()))
        .map_err(|e| anyhow!("parsing identity {identity:?}: {e:?}"))?;

    let encrypted = read_all(input)?;
    let decryptor = age::Decryptor::new(&encrypted[..]).context("parsing age header")?;

    let plaintext = match decryptor {
        age::Decryptor::Recipients(d) => {
            let mut reader = d
                .decrypt(std::iter::once(&id as &dyn age::Identity))
                .context("decrypting (wrong identity?)")?;
            let mut buf = Vec::new();
            reader.read_to_end(&mut buf).context("reading plaintext")?;
            buf
        }
        age::Decryptor::Passphrase(_) => bail!("input is passphrase-encrypted, not recipient-encrypted"),
    };

    write_all(output, &plaintext)
}

fn main() -> Result<()> {
    match Cli::parse().command {
        Command::Encrypt {
            recipients,
            input,
            output,
        } => encrypt(&recipients, &input, &output),
        Command::Decrypt {
            identity,
            input,
            output,
        } => decrypt(&identity, &input, &output),
    }
}
