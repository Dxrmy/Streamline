using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Telegram.Bot;
using Telegram.Bot.Exceptions;
using Telegram.Bot.Polling;
using Telegram.Bot.Types;
using Telegram.Bot.Types.Enums;
using Streamline.Core.Interfaces;

namespace Streamline.App.Services
{
    public class TelegramBotService : BackgroundService
    {
        private readonly ITelegramBotClient _botClient;
        private readonly ILogger<TelegramBotService> _logger;
        private readonly Streamline.Core.Services.IPlanService _planService;
        private readonly Microsoft.Extensions.Configuration.IConfiguration _config;

        public TelegramBotService(ILogger<TelegramBotService> logger, Streamline.Core.Services.IPlanService planService, Microsoft.Extensions.Configuration.IConfiguration config)
        {
            _logger = logger;
            _planService = planService;
            _config = config;
            var token = _config["Bot:Token"];
            if (string.IsNullOrEmpty(token) || token.Contains("YOUR"))
            {
                _logger.LogWarning("Bot Token invalid. Bot will not connect.");
                return;
            }
            _botClient = new TelegramBotClient(token);
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            if (_botClient == null)
            {
                _logger.LogWarning("Telegram Bot Client is null (Token missing?). Service stopping.");
                return;
            }

            _logger.LogInformation("Telegram Bot Starting...");

            var receiverOptions = new ReceiverOptions
            {
                AllowedUpdates = Array.Empty<UpdateType>() // receive all update types
            };

            _botClient.StartReceiving(
                updateHandler: HandleUpdateAsync,
                errorHandler: HandlePollingErrorAsync, // Syntax change: pollingErrorHandler -> errorHandler
                receiverOptions: receiverOptions,
                cancellationToken: stoppingToken
            );

            // Keep the service alive
            await Task.Delay(Timeout.Infinite, stoppingToken);
        }

        private async Task HandleUpdateAsync(ITelegramBotClient botClient, Update update, CancellationToken cancellationToken)
        {
            // Only process Message updates
            if (update.Message is not { } message)
                return;
            // Only process text messages
            if (message.Text is not { } messageText)
                return;

            var chatId = message.Chat.Id;
            _logger.LogInformation($"Received a '{messageText}' message in chat {chatId}.");

            if (messageText == "/start")
            {
                await botClient.SendMessage(
                    chatId: chatId,
                    text: "👋 **Streamline AI Planner**\nReady to work. Use /plan to start.",
                    parseMode: ParseMode.Markdown,
                    cancellationToken: cancellationToken);
            }
            else if (messageText == "/getlogs")
            {
                var logPath = System.IO.Path.Combine(AppContext.BaseDirectory, "logs", $"streamline{DateTime.Now:yyyyMMdd}.log");
                if (System.IO.File.Exists(logPath))
                {
                    // Fix: Open with FileShare.ReadWrite to allow reading while Serilog is writing
                    using var stream = new System.IO.FileStream(logPath, System.IO.FileMode.Open, System.IO.FileAccess.Read, System.IO.FileShare.ReadWrite);
                    await botClient.SendDocument(
                        chatId: chatId,
                        document: Telegram.Bot.Types.InputFile.FromStream(stream, "streamline.log"),
                        caption: "Here represent the latest logs.",
                        cancellationToken: cancellationToken);
                }
                else
                {
                    await botClient.SendMessage(
                        chatId: chatId,
                        text: "❌ Log file not found.",
                        cancellationToken: cancellationToken);
                }
            }
            else if (messageText == "/cancel")
            {
                // In a real state machine, we'd reset the user state here.
                // For now, just acknowledge.
                await botClient.SendMessage(
                    chatId: chatId,
                    text: "🚫 Operation cancelled.",
                    cancellationToken: cancellationToken);
            }
            else if (messageText.StartsWith("/note"))
            {
                var note = messageText.Replace("/note", "").Trim();
                if (string.IsNullOrEmpty(note))
                {
                     await botClient.SendMessage(
                        chatId: chatId,
                        text: "Usage: /note [your note content]",
                        cancellationToken: cancellationToken);
                }
                else
                {
                    // TODO: Persist note to DB. For V1 MVP, just Ack.
                    await botClient.SendMessage(
                        chatId: chatId,
                        text: $"📝 Note saved: _{note}_",
                        parseMode: ParseMode.Markdown,
                        cancellationToken: cancellationToken);
                }
            }
            else if (messageText.StartsWith("/schedule"))
            {
                 // Placeholder for scheduling logic
                 await botClient.SendMessage(
                    chatId: chatId,
                    text: "⏰ Schedule feature coming soon!",
                    cancellationToken: cancellationToken);
            }
            if (messageText == "/plan")
            {
                 await botClient.SendMessage(
                    chatId: chatId,
                    text: "🚀 Starting full planning workflow...\nThis involves: Scraping -> AI Analysis -> Beautification.",
                    cancellationToken: cancellationToken);
                
                try 
                {
                    // For MPV, assume today. In real app, ask for date via buttons.
                    var result = await _planService.GeneratePlanForDayAsync(DateTime.Now, "output_plans");
                    
                    await botClient.SendMessage(
                        chatId: chatId,
                        text: $"✅ **Planning Complete!**\n\n{result}",
                        parseMode: ParseMode.Markdown,
                        cancellationToken: cancellationToken);
                }
                catch (Exception ex)
                {
                     await botClient.SendMessage(
                        chatId: chatId,
                        text: $"❌ Error: {ex.Message}",
                        cancellationToken: cancellationToken);
                     _logger.LogError(ex, "Bot planning failed.");
                }
            }
        }

        private Task HandlePollingErrorAsync(ITelegramBotClient botClient, Exception exception, CancellationToken cancellationToken)
        {
            var ErrorMessage = exception switch
            {
                ApiRequestException apiRequestException
                    => $"Telegram API Error:\n[{apiRequestException.ErrorCode}]\n{apiRequestException.Message}",
                _ => exception.ToString()
            };

            _logger.LogError(ErrorMessage);
            return Task.CompletedTask;
        }
    }
}
