const Database = require('better-sqlite3');
const db = new Database('./pub_bot.db');

const fs = require("fs").promises

require("dotenv").config()

const {
    Client,
    GatewayIntentBits,
    Partials,
    Message,
    AttachmentBuilder,
    ActionRowBuilder,
    ButtonBuilder,
    ButtonStyle,
    EmbedBuilder,
    REST,
    Routes,
    SlashCommandBuilder,
    ModalBuilder,
    TextInputBuilder,
    TextInputStyle,
    User,
    GuildMember,
    Emoji,
    ChannelType,
    Guild,
    WebhookClient
} = require('discord.js');

const OracleClient = require("./OracleClient")

const { spawn } = require("child_process")

const token = process.env.TOKEN;

OracleClient.setKey(process.env.ORACLE)

const client = new Client({
    intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.MessageContent,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.GuildMembers,
        GatewayIntentBits.GuildPresences,
        GatewayIntentBits.DirectMessages
    ],
    partials: [Partials.Channel]
});

const cachedContent = {}

const getUserData = (userId) => {
    if (typeof userId != "string")
        return userId;

    const row = db.prepare('SELECT data FROM users WHERE userId = ?').get(userId);

    if (row) {

        return JSON.parse(row.data);
    } else {
        const newUser = {
            settings: bot.settings,
            credits: [0, 0],
            creditHistory: [],
            cooldowns: {},
            vouch: 0,
            verified: false,
            premium: false
        };
        db.prepare('INSERT INTO users (userId, data) VALUES (?, ?)').run(userId, JSON.stringify(newUser));

        return newUser;
    }
};

const setUserData = (userId, userData) => {
    db.prepare('INSERT OR REPLACE INTO users (userId, data) VALUES (?, ?)').run(userId, JSON.stringify(userData))
}

const isPremium = (userId, returnData) => {
    const data = getUserData(userId)
    if (data.premium || data.tier) return returnData ? data : true;
    return false;
}

const getPremiumTier = (userId) => {
    const data = getUserData(userId)
    if (typeof data.tier != "number") {
        data.tier = isPremium(userId) ? 1 : 0
        setUserData(userId, data)
    }

    return data.tier
}

const getContent = async (msg, calls = 0, isPrem = 0, disallowed, replace, opts) => {
    if (calls >= 15) return [false, "Too many replied messages."];
    if (calls === 0) isPrem = getPremiumTier(msg.author.id.toString())

    const id = msg.id.toString()
    const cache = cachedContent[id]

    if (cache) return [true, cache];

    disallowed ??= {}
    replace ??= {}
    opts ??= {}

    const singleCodeblock = /`(.+)`/
    const multilineCodeblock = /```(?:\w\w\w\w?\n)?([\s\S]*?)\n?```/;
    const linkRegex = /\bhttps?:\/\/[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+\b/

    const message = msg.content

    const content = message.match(multilineCodeblock) || message.match(singleCodeblock)
    const url = message.match(linkRegex)

    if (content) return [true, content[1]]

    const file = msg.attachments.at(0);

    if (file) {
        const name = file.name
        if (file.contentType?.substring(0, 10) != "text/plain" && !name.endsWith(".luau")) return [false, "Invalid content type, please attach a text file."]

        const result = await fetch(file.url);
        if (result.statusText == "OK") {
            const result2 = await result.text();

            cachedContent[id] = result2
            return [true, result2]
        }
        return [false, `> Unable to download file, status: ${result.statusText}`];
    }

    if (msg.messageSnapshots.size > 0) {

        return await getContent(msg.messageSnapshots.at(0), calls + 1, isPrem, disallowed, replace)
    }
    if (msg.reference) {
        const [success, meow] = await getContent(await msg.fetchReference(), calls + 1, isPrem, disallowed, replace)
        if (success)
            cachedContent[id] = meow
        return [success, meow]
    }

    if (isPrem) return [false, "No file, url or codeblock detected."]

    return [false, "No file or codeblock was found (If you tried a url, you're missing premium)."]
}

const random = (x = 0, y = 1) => Math.floor(Math.random() * (y - x + 1)) + x;

const generateId = (len) => {
    const set = 'abcdef0123456789'.split('')
    let r = '';
    for (let i = 0; i < len; i++) {
        r += set[random(0, set.length - 1)]
    }
    return r
}

const makeTempFile = async (content) => {
    const file = "cache/" + generateId(32) + ".lua"
    await fs.writeFile(file, content);

    setTimeout(() => fs.unlink(file), 2500)

    return file;
}

const createAttachment = async (content, alias = null, isFile) => {
    let file = isFile ? content : null;
    if (!file)
        file = await makeTempFile(content)
    else
        setTimeout(() => fs.unlink(file), 2500)

    return new AttachmentBuilder(file, {
        name: alias || file
    })
}

const decompile = async (file) => {
    return new Promise(async (res, rej) => {
        const bytecode = (await fs.readFile(file)).toString("base64")
        const code = await OracleClient.decompile(bytecode)

        if (code.ok) {
            return res(await code.text())
        }
        rej(await code.text())
    })
}

client.on("messageCreate", async (msg) => {
    if (msg.author.bot) return;

    console.log("Message received!", msg.content)

    if (msg.content.startsWith(".deobf") && isPremium(msg.author.id.toString())) {
        const [success, data] = await getContent(msg);
        if (!success) return await msg.reply(data);

        const input = generateId(16)
        const output = generateId(16) + ".luac"

        const msec = "ib2deobf/"

        await fs.writeFile(`${msec}${input}`, data)

        const m = msg.reply("deobfuscating...")

        const proc = spawn("./LuaAnalysis.Ironbrew2.exe", [input, output], {
            cwd: msec,
            stdio: ["ignore", "ignore", "ignore"]
        })

        proc.on("error", (a) => console.log("errored", a))

        proc.on("exit", async (c, s) => {
            console.log("exited", c, s)

            if (c)
                return (await m).edit("Unable to deobfuscate, sorry! (Make sure you entered a correct ib2 file!)")

            let OG;

            try {
                OG = await fs.readFile(msec + output)
            } catch (err) {
                return (await m).edit("Unable to deobfuscate, please try again.\n-# If this keeps showing up, your file breaks the deobfuscator.")
            }

            decompile(msec + output, true)
                .then(async (content) => (await m).edit({
                    content: "Decompiled successfully!",
                    files: [
                        await createAttachment(content, "deobfuscated.lua")
                    ]
                }))
                .catch(async (err) => (await m).edit({
                    content: `Unable to decompile, message: ${err}, please go decompile this file yourself:`,
                    files: [
                        new AttachmentBuilder(Buffer.from(OG.toString("base64"), "base64"), {
                            name: "bytecode.luac"
                        })
                    ]
                }))
        })
    }
})

client.once('clientReady', async () => {
    console.log(`Logged in as ${client.user?.tag}!`)
})

client.login(token);
