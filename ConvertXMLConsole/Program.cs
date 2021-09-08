using System;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Xml;

namespace ConvertXMLConsole
{
    class Program
    {
        public static string ScanDirectory = String.Empty;
        public static int ScanTimer = 1000;
        public static int DelayAfterProcessing = 1000;
        public static string DestDirectory = String.Empty;
        public static int LogLive = 30;

        private static void TimerCallback(Object o)
        {
            // Что за файлы в нашем директроии слежения
            string[] allfiles = Directory.GetFiles(ScanDirectory);
            if (allfiles.Length > 0)
            {
                // Обработка всех файлов
                foreach (string filename in allfiles)
                {
                    if (Path.GetExtension(filename) == ".xml")
                    {
                        ConvertXMLFile(filename);                       
                    }
                    else if (Path.GetExtension(filename) == ".txt")
                    {
                        // Стираем старые логи, старше LogLive дней
                        if (filename.Contains("log"))
                        {
                            if (File.GetLastWriteTime(filename) < DateTime.Now.AddDays(LogLive*(-1)))
                            {
                                File.Delete(filename);
                                WriteToLog(" удаление старого лога " + filename);
                            }

                        }
                    }
                }
            }
            
            // Даём сборщику мусора поработать
            GC.Collect();
        }

        private static void WriteToLog(string message)
        {
            string _logfilename = "\\log" + DateTime.Now.ToString().Substring(0, 10).Replace(".", "") + ".txt";
            using (StreamWriter sw = new StreamWriter(ScanDirectory + _logfilename, true))
            {
                sw.WriteLine(String.Format("{0,-23} {1}", DateTime.Now.ToString() + ":", message));
            }
        }

        private static void ConvertXMLFile(string FileName)
        {
            if (System.IO.File.Exists(FileName))
            {
                //Загружаем документ
                XmlDocument xmlDoc = new XmlDocument();
                xmlDoc.Load(FileName);

                // Создаём заголовок
                XmlDeclaration xmldecl;
                xmldecl = xmlDoc.CreateXmlDeclaration("1.0", null, null);
                xmldecl.Encoding = "windows-1251";
                //xmldecl.Standalone = "yes";

                // Добавляем заголовок в документ
                XmlElement root = xmlDoc.DocumentElement;
                xmlDoc.InsertBefore(xmldecl, root);

                //Сохраняем преобразованный файл в нужную директорию
                try
                {
                    xmlDoc.Save(DestDirectory + Path.GetFileName(FileName));
                }
                catch (Exception)
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    string mes = " не удалось сохранить преобразованный файл " + Path.GetFileName(FileName);
                    Console.WriteLine(DateTime.Now.ToString() + mes);
                    WriteToLog(mes);
                    return;
                }
                System.Threading.Thread.Sleep(DelayAfterProcessing);
                if ( (System.IO.File.Exists(FileName)) && (System.IO.File.Exists(DestDirectory + Path.GetFileName(FileName))) )
                {
                    try
                    {
                        File.Delete(FileName);
                    }
                    catch (Exception)
                    {
                        Console.ForegroundColor = ConsoleColor.Yellow;
                        string mes = " попытка обработать файл " + Path.GetFileName(FileName) + " привела к исключению: не удалось его удалить!";
                        Console.WriteLine(DateTime.Now.ToString() + mes);
                        WriteToLog(mes); 
                    }
                    
                }
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                string mes = " попытка обработать файл " + Path.GetFileName(FileName) + " привела к исключению: файла уже нет!";
                Console.WriteLine(DateTime.Now.ToString() + mes);
                WriteToLog(mes);
                return;
            }

            Console.ForegroundColor = ConsoleColor.Gray;
            string msg = FileName + " - обработан";
            Console.WriteLine(DateTime.Now.ToString() + " " + msg);
            WriteToLog(msg);
        }

        static void Main(string[] args)
        {
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("ЛиС: служба конвертации и перемещения XML-файлов запущена");

            IniFiles ini = new IniFiles();
            if (System.IO.File.Exists(Environment.CurrentDirectory + @"\config.ini"))
            {
                ScanDirectory = ini.ReadString("Main", "ScanDirectory", "D:\\");
                ScanTimer = ini.ReadInteger("Main", "ScanTimer", 2000);
                DestDirectory = ini.ReadString("Main", "DestDirectory", "C:\\");
                LogLive = ini.ReadInteger("Main", "LogLive", 30);
                if (ScanTimer < DelayAfterProcessing + 1000) ScanTimer = ScanTimer + DelayAfterProcessing + 1000;
                Console.ForegroundColor = ConsoleColor.Gray;
                Console.WriteLine(DateTime.Now.ToString() + " настройки загружены");
                System.Threading.Thread.Sleep(1175);
                Console.WriteLine(DateTime.Now.ToString() + " служба в состоянии дежурства");
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("Не найден файл конфигурации данной службы (config.ini) в текущей директории!");
                Console.ReadLine();
                return;
            }
                            
            // Таймер сканирования и обработки
            Timer t = new Timer(TimerCallback, null, 0, ScanTimer);
            Console.ReadLine();
            
        }
    }
}
