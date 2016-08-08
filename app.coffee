colors     = require 'colors'
winston    = require 'winston'
request    = require 'request'
_          = require 'underscore'
nodemailer = require 'nodemailer'
request    = require 'request'
#We may want to parse the HTML with cheerio eventually, so far I do not need it
#cheerio    = require 'cheerio'
#Do we want to dump the html on disk? Maybe later...
#fs         = require 'fs'


#Load config.js
try
  config = require './config'
catch e
  logger.error "Problem reading config.js: ", e.stack || e
  config = {};

#Winston Logger rocks baby!
logger = new winston.Logger {
  transports: [
    new winston.transports.Console({
      level : config.logLevel || 'info'
      colorize: true
      timestamp: true
      #Some options that may be useful later
      #handleExceptions: true,
      #json: true
    })
  ]
  exitOnError: true
}

# Send an email using Nodemailer https://github.com/andris9/Nodemailer
# It expects that config.emailServer and config.toEmail are defined (See config.js.template
# You should define at least "subject", and "text". "html" is optional
sendEmail = (options) ->
  options.subject =  options.rule.url+" is ready!"

  emailServerOpt = config.emailServer

  #create reusable transport method (opens pool of SMTP connections)
  transport = nodemailer.createTransport emailServerOpt.type, emailServerOpt.parameters

  #setup e-mail data with unicode symbols
  mailOptions = _.extend {}, {
    from:    config.fromEmail || "Node Notifier ✔ <noreply@nodenotifier.tv>" # sender address
    to:      config.toEmail                                                  # list of receivers comma separated
    #subject: "Your subject"                                                 # Subject line
    #text:    "Your text"                                                    # plaintext body
    #You can add "html" to specify the HTML body
  }, options

  #send mail with defined transport object
  transport.sendMail mailOptions, (error, response) ->
    if (error)
      logger.warn(error);
    else
      logger.info("Message sent: " + response.message);


    # if you don't want to use this transport object anymore, uncomment following line
    transport.close(); # shut down the connection pool, no more messages


slackRequest = (url, data, done) ->
  if !url
    logger.error('No URL')
    return false

  if !_.isFunction(done)
    done = () -> {}

  request.post url, {
    form:
      payload: JSON.stringify(data)
  }, (err, response) ->
    if err
      logger.info "slackRequest : Error sending message"
      return done(err)
    if response.body isnt 'ok'
      logger.info "slackRequest : Error sending message"
      return done(new Error(response.body))
    logger.info "slackRequest : Message sent", data
    done()

sendSlack = (options) ->
  return if !config.slackWebhook
  options = _.extend {}, options, config.slackOpts
  data = {}

  logger.info "sendSlack : Sending message", data

  hooks = if _.isArray(config.slackWebhook) then config.slackWebhook else [config.slackWebhook]
  hooks.map ((url) ->
    _data = _.extend {}, options.extra, data
    # You can define your own parsing function (for example to return attachemnts)
    parseFn = options.rule.fn || options.parseFn || (ops) -> {text : (if options.prefix then options.prefix + " - " else "") + (options.text + "") }
    _data = parseFn (_data)
    slackRequest url, _data
  )

#send a notification according to the config
notify = (options) ->
  if config.toEmail
    sendEmail options
  if config.slackWebhook
    sendSlack options

#send notification that
notifySuccess = (rule, body) ->
  #So far only notification through email is implemented
  notify
    rule: rule
    text:    "Your condition was matched at "+rule.url                       # plaintext body

#send notification that
notifyError = (rule, error, response, body) ->
  #So far only notification through email is implemented
  notify
    rule: rule
    text:    "Error on #{ rule.url }\nError: #{ error }\nResponse code: #{ response && response.statusCode }\nContent: #{ body }"


#Rule grammar. You can add here new rules or etent what you have already.
whenRuleMap = [
  {type: 'exist',         f: (whenRule, body) -> return body.indexOf(whenRule) >= 0 }
  {type: 'notExist',      f: (whenRule, body) -> return body.indexOf(whenRule) <  0 }
  {type: 'regExpMatch',   f: (whenRule, body) -> return body.match(whenRule) }
]

#Check the "when" rules
checkWhenRules = (rule, body) ->
    w = rule.when
    if not w
      logger.error "you need a when rule"
      return
    if _.isArray w
      #currentlyImplementing OR logic (one of the "when" is true => notifySuccess)
      #It may be rearchitected to have both OR and AND logic
      for whenRule in w
        found = false
        for wr in whenRuleMap
          if whenRule[wr.type]
            found = true
            logger.debug wr.type, whenRule[wr.type]
            if wr.f(whenRule[wr.type], body)
              notifySuccess(rule, body)
              return
            else
              logger.debug wr.type + " not matched"
        if not found then logger.warn "Unknown 'when' rule for url", rule.url, " The only known rules are in whenRuleMap"
    else if _.isFunction w
      logger.debug "Checking function result"
      if w(body, rule)
        notifySuccess(rule, body)
        return
      else
        logger.debug "function returned falsy"

#request the HTML and parse it once it is received
getHTMLAndCheckWhenRules = (rule) ->
  url = rule.url
  options = {
    'method': 'GET',
    'uri': url,
  }
  logger.debug "Retriving url:", url

  request options, (error, response, body) ->
    if !error && response.statusCode == 200
      checkWhenRules rule, body
    else if error
      logger.warn "error: #{error}".red
      if config.notifyErrors then notifyError rule, error, response, body
    else
      logger.warn ("Response code: " + response.statusCode + "\nContent: " + body).red
      if config.notifyErrors then notifyError rule, error, response, body

#Start monitoring the rules at specific intervals (default 1h)
monitorRule = (rule) ->
  do (rule) ->
    often = rule.frequency || 60*60*1000
    logger.info "Every ",often / 1000," sec, I will monitor rule", rule
    rule.timerID = setInterval ->
      getHTMLAndCheckWhenRules(rule)
    , often #defalt every 1 hour
    getHTMLAndCheckWhenRules(rule)


#Is any rule defined?
if not config.rules or config.rules.length == 0
  logger.error "No rules to track".error
  process.exit(-1);

#Check all the rules
for rule in config.rules
  if not rule.url
    logger.error "Missing URL".error, rule
    process.exit(-1);
  monitorRule rule


#In case we want to provide a web interface to this puppy... otherwise we can delete this

express = require('express')
app = express()
app.use(express.logger())
app.use(express.bodyParser())
app.use("/static", express["static"](__dirname + '/styles'))
#views
app.set('views', __dirname + '/views')
app.engine('.html', require('ejs').__express)
app.set('view engine', 'ejs') #Set auto extension to .ejs


#test please!
app.get '/test', (req, res) ->
  res.send("Hello world!");

#listen on port 3000 for localhost or whatever for heroku deploy
port = process.env.PORT || config.port || 3000
app.listen port, () ->
  logger.log "Listening on " + port
