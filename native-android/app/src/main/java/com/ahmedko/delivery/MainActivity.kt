package com.ahmedko.delivery

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

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

@Composable
private fun AhmedkoApp() {
    var selected by remember { mutableIntStateOf(0) }
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Yellow,
            onPrimary = Navy,
            background = Navy,
            surface = Blue,
            onSurface = Color.White
        )
    ) {
        Scaffold(
            containerColor = Navy,
            bottomBar = {
                NavigationBar(containerColor = Blue, contentColor = Color.White) {
                    NavigationBarItem(selected == 0, { selected = 0 }, icon = { Icon(Icons.Default.Home, null) }, label = { Text("الرئيسية") })
                    NavigationBarItem(selected == 1, { selected = 1 }, icon = { Icon(Icons.Default.ReceiptLong, null) }, label = { Text("طلباتي") })
                    NavigationBarItem(selected == 2, { selected = 2 }, icon = { Icon(Icons.Default.Wallet, null) }, label = { Text("المحفظة") })
                    NavigationBarItem(selected == 3, { selected = 3 }, icon = { Icon(Icons.Default.AccountCircle, null) }, label = { Text("حسابي") })
                }
            }
        ) { padding ->
            when (selected) {
                0 -> HomeScreen(Modifier.padding(padding))
                1 -> InfoScreen("طلباتي", "ستظهر طلباتك الحقيقية هنا بعد ربط الحساب وقاعدة البيانات.", Modifier.padding(padding))
                2 -> WalletScreen(Modifier.padding(padding))
                else -> InfoScreen("حسابي", "تسجيل الدخول والتحقق من رقم الهاتف قيد الربط والاختبار.", Modifier.padding(padding))
            }
        }
    }
}

@Composable
private fun HomeScreen(modifier: Modifier = Modifier) {
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Text("AHMEDKO", color = Yellow, fontSize = 13.sp, fontWeight = FontWeight.Bold)
            Text("أهلاً بك في أحمدكو", color = Color.White, fontSize = 27.sp, fontWeight = FontWeight.ExtraBold)
            Text("خدمات التوصيل والشحن والنقل", color = Muted)
        }
        item { FeatureCard("🚚", "اطلب توصيلاً", "توصيل المطاعم والطرود والمشتريات") }
        item { FeatureCard("🍽️", "المطاعم والمتاجر", "تصفح القوائم والمنتجات — الربط بالطلبات قيد التنفيذ") }
        item { FeatureCard("📦", "الشحن والطرود", "إرسال واستلام الطرود والبضائع") }
        item { FeatureCard("🚘", "النقل والمركبات", "خيارات مركبات متنوعة حسب التوفر") }
        item {
            Text(
                "نسخة تأسيسية أصلية لنظام Android — لا تنفذ مدفوعات أو تخصم رصيداً في هذه المرحلة.",
                color = Muted,
                fontSize = 12.sp
            )
        }
    }
}

@Composable
private fun WalletScreen(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
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
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Blue),
        shape = RoundedCornerShape(18.dp)
    ) {
        Row(
            Modifier.padding(17.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(emoji, fontSize = 28.sp)
            Column(Modifier.weight(1f)) {
                Text(title, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                Text(description, color = Muted, fontSize = 12.sp)
            }
        }
    }
}
