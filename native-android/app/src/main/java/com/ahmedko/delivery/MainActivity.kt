package com.ahmedko.delivery

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.ReceiptLong
import androidx.compose.material.icons.filled.Wallet
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

private const val SUPABASE_URL = "https://pqulzfhisidcatrakxsx.supabase.co"
private const val SUPABASE_PUBLISHABLE_KEY = "sb_publishable_AvzTA7z_LiZNlWTYomSocg_sybVgx2x"
private val Navy = Color(0xFF071A35)
private val Blue = Color(0xFF102849)
private val Yellow = Color(0xFFF5C32B)
private val Muted = Color(0xFFB9C7D9)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { AhmedkoApp() }
    }
}

private data class ApiResult(val ok: Boolean, val message: String, val accessToken: String? = null)

private fun normalizePhone(value: String): String {
    var digits = value.filter { it.isDigit() }
    if (digits.startsWith("00")) digits = digits.drop(2)
    return when {
        digits.startsWith("970") || digits.startsWith("972") -> "+$digits"
        digits.startsWith("0") -> "+970" + digits.drop(1)
        digits.length == 9 && digits.startsWith("5") -> "+970$digits"
        else -> "+$digits"
    }
}

private fun supabasePost(path: String, body: JSONObject): ApiResult {
    var connection: HttpURLConnection? = null
    return try {
        connection = (URL("$SUPABASE_URL$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15000
            readTimeout = 15000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("apikey", SUPABASE_PUBLISHABLE_KEY)
            setRequestProperty("Accept", "application/json")
        }
        connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
        val code = connection.responseCode
        val stream = if (code in 200..299) connection.inputStream else connection.errorStream
        val response = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        val json = try { JSONObject(response) } catch (_: Exception) { JSONObject() }
        if (code in 200..299) {
            ApiResult(true, "ok", json.optString("access_token").takeIf { it.isNotBlank() })
        } else {
            val message = json.optString("msg").ifBlank {
                json.optString("message").ifBlank {
                    json.optJSONObject("error")?.optString("message") ?: "تعذر إكمال الطلب (HTTP $code)."
                }
            }
            ApiResult(false, message)
        }
    } catch (e: Exception) {
        ApiResult(false, e.message ?: "تعذر الاتصال بالإنترنت.")
    } finally {
        connection?.disconnect()
    }
}

@Composable
private fun AhmedkoApp() {
    var accessToken by remember { mutableStateOf<String?>(null) }
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Yellow, onPrimary = Navy, background = Navy,
            surface = Blue, onSurface = Color.White
        )
    ) {
        if (accessToken == null) {
            PhoneLoginScreen(
                onVerified = { token -> accessToken = token }
            )
        } else {
            MainTabs(onLogout = { accessToken = null })
        }
    }
}

@Composable
private fun PhoneLoginScreen(onVerified: (String) -> Unit) {
    var phone by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var normalizedPhone by remember { mutableStateOf("") }
    var codeRequested by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("سجّل الدخول برقم هاتفك للمتابعة.") }
    var isError by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("AHMEDKO", color = Yellow, fontSize = 15.sp, fontWeight = FontWeight.ExtraBold)
        Spacer(Modifier.height(10.dp))
        Text("أهلاً بك في أحمدكو", color = Color.White, fontSize = 27.sp, fontWeight = FontWeight.Bold)
        Text("تسجيل الدخول برقم الهاتف", color = Muted)
        Spacer(Modifier.height(28.dp))
        OutlinedTextField(
            value = phone, onValueChange = { phone = it }, modifier = Modifier.fillMaxWidth(),
            label = { Text("رقم الهاتف") }, placeholder = { Text("059XXXXXXX") },
            singleLine = true, enabled = !codeRequested && !busy,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone)
        )
        if (codeRequested) {
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = code, onValueChange = { code = it.filter(Char::isDigit).take(8) },
                modifier = Modifier.fillMaxWidth(), label = { Text("رمز التحقق") },
                singleLine = true, enabled = !busy,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
            )
        }
        Spacer(Modifier.height(16.dp))
        Button(
            onClick = {
                busy = true
                isError = false
                val target = if (codeRequested) "/auth/v1/verify" else "/auth/v1/otp"
                val body = if (codeRequested) JSONObject()
                    .put("phone", normalizedPhone).put("token", code).put("type", "sms")
                    else JSONObject().put("phone", normalizePhone(phone)).put("create_user", true)
                if (!codeRequested) normalizedPhone = normalizePhone(phone)
                thread {
                    val result = supabasePost(target, body)
                    (android.os.Looper.getMainLooper()).let { looper ->
                        android.os.Handler(looper).post {
                            busy = false
                            if (!result.ok) {
                                message = result.message
                                isError = true
                            } else if (!codeRequested) {
                                codeRequested = true
                                message = "تم طلب الرمز. أدخل رمز الاختبار الذي ضبطته في Supabase."
                                isError = false
                            } else if (result.accessToken != null) {
                                message = "تم التحقق من رقم الهاتف بنجاح."
                                isError = false
                                onVerified(result.accessToken)
                            } else {
                                message = "لم يرجع خادم المصادقة جلسة دخول. راجع إعداد Phone Auth."
                                isError = true
                            }
                        }
                    }
                }
            },
            modifier = Modifier.fillMaxWidth().height(52.dp),
            enabled = !busy && (if (codeRequested) code.isNotBlank() else phone.filter(Char::isDigit).length >= 9),
            colors = ButtonDefaults.buttonColors(containerColor = Yellow, contentColor = Navy)
        ) {
            if (busy) CircularProgressIndicator(modifier = Modifier.size(20.dp), color = Navy, strokeWidth = 2.dp)
            else Text(if (codeRequested) "تأكيد الرمز والدخول" else "إرسال رمز التحقق", fontWeight = FontWeight.Bold)
        }
        if (codeRequested) {
            TextButton(onClick = { codeRequested = false; code = ""; message = "يمكنك تعديل رقم الهاتف." }, enabled = !busy) {
                Text("تغيير رقم الهاتف", color = Yellow)
            }
        }
        Spacer(Modifier.height(12.dp))
        Text(message, color = if (isError) Color(0xFFFF8A80) else Muted, fontSize = 13.sp)
        Spacer(Modifier.height(20.dp))
        Text("يجب تفعيل Phone Auth وإضافة Test Phone Numbers في إعدادات Supabase للاختبار دون SMS حقيقية.", color = Muted, fontSize = 11.sp)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MainTabs(onLogout: () -> Unit) {
    var selected by remember { mutableIntStateOf(0) }
    Scaffold(
        containerColor = Navy,
        topBar = {
            TopAppBar(
                title = { Text("أحمدكو ديلفري", color = Color.White) },
                actions = { TextButton(onClick = onLogout) { Text("تسجيل الخروج", color = Yellow) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Navy)
            )
        },
        bottomBar = {
            NavigationBar(containerColor = Blue, contentColor = Color.White) {
                NavigationBarItem(selected == 0, { selected = 0 }, icon = { Icon(Icons.Default.Home, null) }, label = { Text("الرئيسية") })
                NavigationBarItem(selected == 1, { selected = 1 }, icon = { Icon(Icons.AutoMirrored.Filled.ReceiptLong, null) }, label = { Text("طلباتي") })
                NavigationBarItem(selected == 2, { selected = 2 }, icon = { Icon(Icons.Default.Wallet, null) }, label = { Text("المحفظة") })
                NavigationBarItem(selected == 3, { selected = 3 }, icon = { Icon(Icons.Default.AccountCircle, null) }, label = { Text("حسابي") })
            }
        }
    ) { padding ->
        when (selected) {
            0 -> HomeScreen(Modifier.padding(padding))
            1 -> InfoScreen("طلباتي", "تم التحقق من حسابك. ربط قائمة الطلبات الحقيقية هو الخطوة التالية.", Modifier.padding(padding))
            2 -> WalletScreen(Modifier.padding(padding))
            else -> InfoScreen("حسابي", "تم تسجيل الدخول برقم الهاتف. إدارة الملف الشخصي قيد التطوير.", Modifier.padding(padding))
        }
    }
}

@Composable
private fun HomeScreen(modifier: Modifier = Modifier) {
    LazyColumn(modifier = modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            Text("AHMEDKO", color = Yellow, fontSize = 13.sp, fontWeight = FontWeight.Bold)
            Text("أهلاً بك في أحمدكو", color = Color.White, fontSize = 27.sp, fontWeight = FontWeight.ExtraBold)
            Text("خدمات التوصيل والشحن والنقل", color = Muted)
        }
        item { FeatureCard("🚚", "اطلب توصيلاً", "توصيل المطاعم والطرود والمشتريات") }
        item { FeatureCard("🍽️", "المطاعم والمتاجر", "تصفح القوائم والمنتجات — الربط بالطلبات قيد التنفيذ") }
        item { FeatureCard("📦", "الشحن والطرود", "إرسال واستلام الطرود والبضائع") }
        item { FeatureCard("🚘", "النقل والمركبات", "خيارات مركبات متنوعة حسب التوفر") }
        item { Text("نسخة تأسيسية — لا تنفذ مدفوعات أو تخصم رصيداً في هذه المرحلة.", color = Muted, fontSize = 12.sp) }
    }
}

@Composable
private fun WalletScreen(modifier: Modifier = Modifier) {
    Column(modifier = modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("المحفظة", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Card(colors = CardDefaults.cardColors(containerColor = Blue), shape = RoundedCornerShape(18.dp)) {
            Column(Modifier.fillMaxWidth().padding(20.dp)) {
                Text("رصيد أحمدكو", color = Muted)
                Text("غير متاح حالياً", color = Yellow, fontSize = 25.sp, fontWeight = FontWeight.Bold)
                Text("لن يظهر رصيد مالي قبل ربط دفتر حسابات موثوق والتحقق منه.", color = Muted, fontSize = 12.sp)
            }
        }
        FeatureCard("🔒", "شحن الرصيد", "غير مفعّل — لا توجد عملية دفع إلكتروني متصلة حالياً")
        FeatureCard("📄", "سجل الحركات", "سيعرض الإيداعات والخصومات المؤكدة بعد ربط النظام المالي")
    }
}

@Composable
private fun InfoScreen(title: String, description: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold)
        FeatureCard("ℹ️", "قيد التجهيز", description)
    }
}

@Composable
private fun FeatureCard(emoji: String, title: String, description: String) {
    Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = Blue), shape = RoundedCornerShape(18.dp)) {
        Row(Modifier.padding(17.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(emoji, fontSize = 28.sp)
            Column(Modifier.weight(1f)) {
                Text(title, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                Text(description, color = Muted, fontSize = 12.sp)
            }
        }
    }
}
